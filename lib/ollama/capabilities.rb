# frozen_string_literal: true

module Ollama
  # Automatically infers model capabilities (tools, thinking, vision, embeddings)
  # based on the model's native `family`, `families`, and `name`.
  module Capabilities
    class << self
      # Returns a hash of boolean capabilities.
      # Prefers server-provided capabilities array from /api/show when available,
      # and falls back to model family and name heuristics.
      # @param model_info [Hash] A model entry from `/api/tags` or `/api/show`
      # @return [Hash] { "tools" => true, "thinking" => false, ... }
      def for(model_info)
        name = model_info["name"] || ""
        server_caps = Array(model_info["capabilities"]).map(&:to_s).map(&:downcase) if model_info["capabilities"].is_a?(Array)

        # Details may be nested under 'details' in list/tags, or at top level in show
        details = model_info["details"] || model_info || {}

        family = details["family"] || ""
        families = details["families"] || [family]

        {
          "tools" => resolve_cap(server_caps, "tools") { tools_supported?(families, name) },
          "thinking" => resolve_cap(server_caps, "thinking") { thinking_supported?(families, name) },
          "vision" => resolve_cap(server_caps, "vision") { vision_supported?(families, name) },
          "embeddings" => resolve_cap(server_caps, %w[embeddings embedding]) { embeddings_supported?(families, name) }
        }
      end

      TOOLS_FAMILIES = %w[llama qwen2 qwen3 qwen3vl command-r mistral gemma2 gemma4].freeze
      THINKING_MODELS = [/deepseek-r1/i, /-r1/i, /qwq/i, /\bqwen3(?![.\d])/i, /gemma[_-]?4/i].freeze
      VISION_FAMILIES = %w[llava clip qwen3vl mllama].freeze
      VISION_MODELS = [/vision/i, /vl/i].freeze
      EMBEDDING_FAMILIES = %w[nomic-bert bert mxbai-embed-large].freeze
      EMBEDDING_MODELS = [/embed/i, /minilm/i].freeze

      private

      def resolve_cap(server_caps, keys)
        return Array(keys).any? { |k| server_caps.include?(k) } if server_caps

        yield
      end

      def tools_supported?(families, name)
        return false if name&.match?(/codellama/i)

        families.any? { |f| TOOLS_FAMILIES.include?(f.to_s.downcase) }
      end

      def thinking_supported?(_families, name)
        return false if name.nil? || name.empty?

        THINKING_MODELS.any? { |regex| name.match?(regex) }
      end

      def vision_supported?(families, name)
        families.any? { |f| VISION_FAMILIES.include?(f.to_s.downcase) } ||
          (name && VISION_MODELS.any? { |regex| name.match?(regex) })
      end

      def embeddings_supported?(families, name)
        families.any? { |f| EMBEDDING_FAMILIES.include?(f.to_s.downcase) } ||
          (name && EMBEDDING_MODELS.any? { |regex| name.match?(regex) })
      end
    end
  end
end

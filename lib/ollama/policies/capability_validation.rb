# frozen_string_literal: true

require_relative "base"

module Ollama
  module Policies
    # CapabilityValidation policy - validates model capabilities before request
    class CapabilityValidation < Base
      attr_reader :enabled, :cache, :hooks

      # @param enabled [Boolean] Whether capability validation is enabled (default: true)
      # @param cache [Object] Cache store for model profiles (must respond to read/write)
      # @param cache_ttl [Integer] Cache TTL in seconds (default: 3600)
      # @param hooks [Hash] Optional hooks: :capability_missing, :model_unknown
      def initialize(enabled: true, cache: nil, cache_ttl: 3600, hooks: {})
        super()
        @enabled = enabled
        @cache = cache
        @cache_ttl = cache_ttl
        @hooks = hooks
      end

      def around(request, env, &block)
        return block.call(request, env) unless @enabled

        # Skip if no model or endpoint doesn't require capabilities
        return block.call(request, env) unless validate_capabilities?(request)

        model = request_model(request)
        return block.call(request, env) unless model

        # Get model profile (with caching)
        profile = get_model_profile(model)

        # Check capabilities
        missing = check_capabilities(request, profile)
        return block.call(request, env) if missing.empty?

        @hooks[:capability_missing]&.call(missing, model, env)

        raise UnsupportedCapabilityError,
              "Model '#{model}' does not support: #{missing.join(", ")}"
      end

      private

      def validate_capabilities?(request)
        # Only validate for endpoints that may require specific capabilities
        %i[chat generate embeddings].include?(endpoint(request))
      end

      def get_model_profile(model)
        cache_key = "model_profile:#{model}"

        if @cache && (cached = @cache.read(cache_key))
          return cached
        end

        # Infer capabilities from the model name pattern
        require_relative "../model_profile"
        profile = Ollama::ModelProfile.for(model)

        @cache&.write(cache_key, profile, expires_in: @cache_ttl)

        profile
      end

      def check_capabilities(request, profile)
        body = body_hash(request)
        missing = []

        # Check thinking capability
        missing << "thinking" if body["think"] && !profile.thinking?

        # Check vision capability
        missing << "vision" if body["images"] && !profile.supports_modality?(:image)

        # Check tools capability
        missing << "tools" if body["tools"] && !profile.tool_calling?

        # Check structured output capability
        missing << "structured_output" if body["format"] && !profile.structured_output?

        missing
      end
    end
  end
end

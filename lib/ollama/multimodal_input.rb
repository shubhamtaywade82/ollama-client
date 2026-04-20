# frozen_string_literal: true

module Ollama
  # Typed input builder for multimodal chat messages.
  #
  # Handles modality ordering (image/audio before text for Gemma 4),
  # rejects modalities unsupported by the active model profile, and
  # converts the typed part list into a plain message hash.
  #
  # Usage:
  #   input = MultimodalInput.build(
  #     [
  #       { type: :image, data: image_bytes, token_budget: 560 },
  #       { type: :text,  data: "Summarize this chart." }
  #     ],
  #     profile: profile
  #   )
  #   message = input.to_message  # { role: "user", content: "...", images: [...] }
  class MultimodalInput
    SUPPORTED_TYPES = %i[text image audio].freeze

    attr_reader :parts

    def initialize
      @parts = []
    end

    # Build and reorder inputs for a given profile.
    # @param inputs [Array<Hash>] Each hash: { type:, data:, token_budget: (optional) }
    # @param profile [ModelProfile]
    # @return [MultimodalInput]
    def self.build(inputs, profile:)
      obj = new
      inputs.each { |part| obj.add(part, profile: profile) }
      obj.reorder!(profile.modality_order)
      obj
    end

    # Add a single input part, validating type and profile support.
    # @param part [Hash] { type: Symbol, data: Object, token_budget: Integer (optional) }
    # @param profile [ModelProfile, nil]
    def add(part, profile: nil)
      type = part[:type].to_sym
      unless SUPPORTED_TYPES.include?(type)
        raise ArgumentError, "Unsupported input type: #{type}. Must be one of: #{SUPPORTED_TYPES.join(", ")}"
      end

      if profile && !profile.supports_modality?(type)
        raise UnsupportedCapabilityError,
              "Model '#{profile.model_name}' does not support #{type} input"
      end

      @parts << { type: type, data: part[:data], token_budget: part[:token_budget] }.compact
    end

    # Reorder parts by the profile's preferred modality order.
    # @param order [Array<Symbol>]
    # @return [self]
    def reorder!(order)
      @parts.sort_by! { |p| order.index(p[:type]) || 999 }
      self
    end

    # Build a user message hash from the typed parts.
    # Images are extracted into the :images key; text is joined.
    # @param role [String]
    # @return [Hash]
    def to_message(role: "user")
      text  = @parts.select { |p| p[:type] == :text  }.map { |p| p[:data] }.join("\n")
      imgs  = @parts.select { |p| p[:type] == :image }.map { |p| p[:data] }

      msg = { role: role, content: text }
      msg[:images] = imgs unless imgs.empty?
      msg
    end
  end
end

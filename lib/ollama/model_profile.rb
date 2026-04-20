# frozen_string_literal: true

module Ollama
  # Maps model name patterns to a capability profile.
  # The profile drives prompt adaptation, streaming event routing,
  # history sanitization policy, and model-aware option defaults.
  #
  # Usage:
  #   profile = Ollama::ModelProfile.for("gemma4:31b-cloud")
  #   profile.thinking?           # => true
  #   profile.history_policy      # => :exclude_thoughts
  #   profile.default_options     # => { temperature: 1.0, top_p: 0.95, top_k: 64 }
  class ModelProfile
    FAMILIES = {
      gemma4: {
        pattern: /\bgemma[_-]?4\b/i,
        thinking: true,
        multimodal: %i[text image],
        audio: false,
        tool_calling: true,
        structured_output: true,
        stream_reasoning: true,
        keep_reasoning_separate: true,
        history_policy: :exclude_thoughts,
        think_trigger: :system_prompt_tag,
        think_tag: "<|think|>",
        default_temperature: 1.0,
        default_top_p: 0.95,
        default_top_k: 64,
        context_window: 128_000,
        modality_order: %i[image audio text]
      },
      deepseek: {
        pattern: /\bdeepseek\b/i,
        thinking: true,
        multimodal: %i[text],
        audio: false,
        tool_calling: false,
        structured_output: true,
        stream_reasoning: true,
        keep_reasoning_separate: true,
        history_policy: :exclude_thoughts,
        think_trigger: :flag,
        default_temperature: 0.6,
        default_top_p: 0.95,
        context_window: 64_000,
        modality_order: %i[text]
      },
      qwen: {
        pattern: /\bqwen\d*/i,
        thinking: true,
        multimodal: %i[text image],
        audio: false,
        tool_calling: true,
        structured_output: true,
        stream_reasoning: true,
        keep_reasoning_separate: true,
        history_policy: :exclude_thoughts,
        think_trigger: :flag,
        default_temperature: 0.7,
        default_top_p: 0.95,
        context_window: 128_000,
        modality_order: %i[image text]
      },
      embedding: {
        pattern: /\b(?:nomic-embed|mxbai-embed|bge-|embed-|minilm)\b/i,
        thinking: false,
        multimodal: %i[text],
        audio: false,
        tool_calling: false,
        structured_output: false,
        stream_reasoning: false,
        keep_reasoning_separate: false,
        history_policy: :none,
        context_window: 8_192,
        modality_order: %i[text]
      }
    }.freeze

    GENERIC_PROFILE = {
      thinking: false,
      multimodal: %i[text],
      audio: false,
      tool_calling: true,
      structured_output: true,
      stream_reasoning: false,
      keep_reasoning_separate: false,
      history_policy: :none,
      context_window: 8_192,
      default_temperature: 0.2,
      default_top_p: 0.9,
      modality_order: %i[text]
    }.freeze

    attr_reader :model_name, :family

    def initialize(model_name, family, capabilities)
      @model_name = model_name.to_s
      @family = family
      @capabilities = capabilities.freeze
    end

    # Detect the capability profile for a model name.
    # @param model_name [String]
    # @return [ModelProfile]
    def self.for(model_name)
      name = model_name.to_s
      FAMILIES.each do |family, profile|
        next unless profile[:pattern]&.match?(name)

        caps = profile.except(:pattern)
        return new(name, family, caps)
      end
      new(name, :generic, GENERIC_PROFILE)
    end

    def thinking?         = !!@capabilities[:thinking]
    def multimodal?       = (@capabilities[:multimodal]&.length.to_i > 1)
    def tool_calling?     = !!@capabilities[:tool_calling]
    def stream_reasoning? = !!@capabilities[:stream_reasoning]
    def structured_output? = !!@capabilities[:structured_output]

    def history_policy  = @capabilities[:history_policy] || :none
    def think_trigger   = @capabilities[:think_trigger]
    def think_tag       = @capabilities[:think_tag]
    def context_window  = @capabilities[:context_window]
    def modality_order  = @capabilities[:modality_order] || %i[text]

    # Whether the model supports a given input modality.
    # @param type [Symbol] :text, :image, or :audio
    def supports_modality?(type)
      (@capabilities[:multimodal] || []).include?(type.to_sym)
    end

    # Model-family-recommended inference options.
    # Returns only keys that have values defined for this family.
    # @return [Hash]
    def default_options
      {
        temperature: @capabilities[:default_temperature],
        top_p: @capabilities[:default_top_p],
        top_k: @capabilities[:default_top_k]
      }.compact
    end

    def to_h
      @capabilities.merge(model: @model_name, family: @family)
    end

    def inspect
      "#<#{self.class.name} model=#{@model_name.inspect} family=#{@family} " \
        "thinking=#{thinking?} multimodal=#{multimodal?} tool_calling=#{tool_calling?}>"
    end
  end
end

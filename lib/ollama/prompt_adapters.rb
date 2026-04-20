# frozen_string_literal: true

require_relative "prompt_adapters/base"
require_relative "prompt_adapters/gemma4"
require_relative "prompt_adapters/qwen"
require_relative "prompt_adapters/deepseek"
require_relative "prompt_adapters/generic"

module Ollama
  module PromptAdapters
    # Return the appropriate adapter for a model profile.
    # @param profile [Ollama::ModelProfile]
    # @return [PromptAdapters::Base]
    def self.for(profile)
      case profile.family
      when :gemma4   then Gemma4.new(profile)
      when :qwen     then Qwen.new(profile)
      when :deepseek then DeepSeek.new(profile)
      else                Generic.new(profile)
      end
    end
  end
end

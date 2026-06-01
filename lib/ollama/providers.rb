# frozen_string_literal: true

require_relative "providers/base"
require_relative "providers/ollama"
require_relative "providers/openai"
require_relative "providers/llama_cpp"

module Ollama
  # API Provider registry and factory.
  module Providers
    # Build the appropriate provider based on configuration.
    # @param config [Ollama::Config]
    # @param transport [Ollama::Transport::Base]
    # @return [Providers::Base]
    def self.build(config, transport)
      case config.provider
      when :ollama, nil
        Ollama.new(config, transport)
      when :openai
        OpenAI.new(config, transport)
      when :llama_cpp
        LlamaCpp.new(config, transport)
      else
        raise ArgumentError, "Unsupported provider: #{config.provider.inspect}"
      end
    end
  end
end

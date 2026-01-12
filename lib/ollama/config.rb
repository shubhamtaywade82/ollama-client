# frozen_string_literal: true

module Ollama
  # Configuration class with safe defaults for agent-grade usage
  #
  # ⚠️ THREAD SAFETY WARNING:
  # Global configuration via OllamaClient.configure is NOT thread-safe.
  # For concurrent agents or multi-threaded applications, use per-client
  # configuration instead:
  #
  #   config = Ollama::Config.new
  #   config.model = "llama3.1"
  #   client = Ollama::Client.new(config: config)
  #
  class Config
    attr_accessor :base_url, :model, :timeout, :retries, :temperature, :top_p, :num_ctx, :on_response

    def initialize
      @base_url = "http://localhost:11434"
      @model = "llama3.1:8b"
      @timeout = 20
      @retries = 2
      @temperature = 0.2
      @top_p = 0.9
      @num_ctx = 8192
      @on_response = nil
    end
  end
end

# frozen_string_literal: true

module Ollama
  # Configuration class with safe defaults for agent-grade usage
  class Config
    attr_accessor :base_url, :model, :timeout, :retries, :temperature, :top_p, :num_ctx

    def initialize
      @base_url = "http://localhost:11434"
      @model = "qwen2.5:7b"
      @timeout = 20
      @retries = 2
      @temperature = 0.2
      @top_p = 0.9
      @num_ctx = 8192
    end
  end
end

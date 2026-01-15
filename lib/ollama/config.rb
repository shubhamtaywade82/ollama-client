# frozen_string_literal: true

require "json"

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

    # Load configuration from JSON file (useful for production deployments)
    #
    # @param path [String] Path to JSON config file
    # @return [Config] New Config instance
    #
    # Example JSON:
    #   {
    #     "base_url": "http://localhost:11434",
    #     "model": "llama3.1:8b",
    #     "timeout": 30,
    #     "retries": 3,
    #     "temperature": 0.2,
    #     "top_p": 0.9,
    #     "num_ctx": 8192
    #   }
    def self.load_from_json(path)
      data = JSON.parse(File.read(path))
      config = new

      config.base_url = data["base_url"] if data.key?("base_url")
      config.model = data["model"] if data.key?("model")
      config.timeout = data["timeout"] if data.key?("timeout")
      config.retries = data["retries"] if data.key?("retries")
      config.temperature = data["temperature"] if data.key?("temperature")
      config.top_p = data["top_p"] if data.key?("top_p")
      config.num_ctx = data["num_ctx"] if data.key?("num_ctx")

      config
    rescue JSON::ParserError => e
      raise Error, "Failed to parse config JSON: #{e.message}"
    rescue Errno::ENOENT
      raise Error, "Config file not found: #{path}"
    end
  end
end

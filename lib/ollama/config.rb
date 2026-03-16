# frozen_string_literal: true

require "json"

module Ollama
  # Configuration class with safe defaults for agent-grade usage
  #
  # ⚠️ THREAD SAFETY WARNING:
  # Global configuration access is mutex-protected, but modifying global config
  # while clients are active can cause race conditions. For concurrent agents
  # or multi-threaded applications, use per-client configuration (recommended):
  #
  #   config = Ollama::Config.new
  #   config.model = "llama3.1"
  #   client = Ollama::Client.new(config: config)
  #
  # Each client instance with its own config is thread-safe.
  #
  class Config
    attr_accessor :base_url, :model, :timeout, :retries, :temperature, :top_p, :num_ctx, :on_response, :strict_json, :api_key

    def initialize
      @base_url = "http://localhost:11434"
      @model = "llama3.2:3b"
      @timeout = 30
      @retries = 2
      @strict_json = true
      @temperature = 0.2
      @top_p = 0.9
      @num_ctx = 8192
      @on_response = nil
      @api_key = nil
    end

    # Set Authorization header on a request when api_key is configured (e.g. for Ollama Cloud).
    # No-op when api_key is nil or empty.
    #
    # @param req [Net::HTTP::Request]
    def apply_auth_to(req)
      return if api_key.nil? || api_key.to_s.strip.empty?

      req["Authorization"] = "Bearer #{api_key}"
    end

    # Load configuration from JSON file (useful for production deployments)
    #
    # @param path [String] Path to JSON config file
    # @return [Config] New Config instance
    #
    # The caller is responsible for ensuring the config path is trusted.
    # Do not pass unvalidated user input directly to this method.
    #
    # Example JSON:
    #   {
    #     "base_url": "http://localhost:11434",
    #     "api_key": "optional-for-ollama-cloud",
    #     "model": "llama3.2:3b",
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
      config.api_key = data["api_key"] if data.key?("api_key")
      config.model = data["model"] if data.key?("model")
      config.timeout = data["timeout"] if data.key?("timeout")
      config.retries = data["retries"] if data.key?("retries")
      config.strict_json = data["strict_json"] if data.key?("strict_json")
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

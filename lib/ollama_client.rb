# frozen_string_literal: true

require_relative "ollama/config"
require_relative "ollama/errors"
require_relative "ollama/schema_validator"
require_relative "ollama/client"
require_relative "ollama/tool_intent"
require_relative "ollama/prompts/tool_planner"

# Main entry point for OllamaClient gem
module OllamaClient
  @config_mutex = Mutex.new
  @warned_thread_config = false

  def self.config
    @config_mutex.synchronize do
      @config ||= Ollama::Config.new
    end
  end

  def self.configure
    if Thread.current != Thread.main && !@warned_thread_config
      @warned_thread_config = true
      warn("[ollama-client] Global OllamaClient.configure is not thread-safe. Prefer per-client config (Ollama::Client.new(config: ...)).")
    end

    @config_mutex.synchronize do
      @config ||= Ollama::Config.new
      yield(@config)
    end
  end
end

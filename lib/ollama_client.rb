# frozen_string_literal: true

require_relative "ollama/config"
require_relative "ollama/errors"
require_relative "ollama/schema_validator"
require_relative "ollama/options"
require_relative "ollama/response"
require_relative "ollama/tool"
require_relative "ollama/client"
require_relative "ollama/document_loader"
require_relative "ollama/streaming_observer"
require_relative "ollama/agent/messages"
require_relative "ollama/agent/planner"
require_relative "ollama/agent/executor"

# Main entry point for OllamaClient gem
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
      msg = "[ollama-client] Global OllamaClient.configure is not thread-safe. " \
            "Prefer per-client config (Ollama::Client.new(config: ...))."
      warn(msg)
    end

    @config_mutex.synchronize do
      @config ||= Ollama::Config.new
      yield(@config)
    end
  end
end

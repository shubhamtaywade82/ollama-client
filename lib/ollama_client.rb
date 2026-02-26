# frozen_string_literal: true

# Load .env file if available (.env takes precedence over shell environment variables)
require "dotenv"
Dotenv.overload

require_relative "ollama/version"
require_relative "ollama/config"
require_relative "ollama/errors"
require_relative "ollama/schema_validator"
require_relative "ollama/options"
require_relative "ollama/response"
require_relative "ollama/client"

# Main entry point for OllamaClient gem
#
# ⚠️ THREAD SAFETY WARNING:
# Global configuration access is protected by mutex, but modifying
# global config while clients are active can cause race conditions.
# For concurrent agents or multi-threaded applications, prefer
# per-client configuration (recommended):
#
#   config = Ollama::Config.new
#   config.model = "llama3.1"
#   client = Ollama::Client.new(config: config)
#
# Each client instance is thread-safe when using its own config.
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
      msg = "[ollama-client] Global OllamaClient.configure called from non-main thread. " \
            "While access is mutex-protected, modifying global config concurrently can cause " \
            "race conditions. Prefer per-client config: Ollama::Client.new(config: ...)"
      warn(msg)
    end

    @config_mutex.synchronize do
      @config ||= Ollama::Config.new
      yield(@config)
    end
  end
end

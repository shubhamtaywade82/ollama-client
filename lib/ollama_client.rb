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
require_relative "ollama/model_profile"
require_relative "ollama/stream_event"
require_relative "ollama/prompt_adapters"
require_relative "ollama/multimodal_input"
require_relative "ollama/history_sanitizer"
require_relative "ollama/client"
require_relative "ollama/tool_intent"
require_relative "ollama/prompts/tool_planner"

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

# Top-level namespace for the Ollama Client SDK
module Ollama
  def self.config
    OllamaClient.config
  end

  def self.configure(&block)
    OllamaClient.configure(&block)
  end

  def self.client
    # We clear the cached client if the config is changed/updated, or just instantiate dynamically
    @client ||= Client.new(config: config)
  end

  def self.chat(messages:, **args)
    client.chat(messages: messages, **args)
  end

  def self.generate(prompt:, **args)
    client.generate(prompt: prompt, **args)
  end

  def self.embed(...)
    client.embeddings.embed(...)
  end
end

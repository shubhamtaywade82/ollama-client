# frozen_string_literal: true

require_relative "ollama/config"
require_relative "ollama/errors"
require_relative "ollama/schema_validator"
require_relative "ollama/client"
require_relative "ollama/tool_intent"
require_relative "ollama/prompts/tool_planner"

# Main entry point for OllamaClient gem
module OllamaClient
  def self.config
    @config ||= Ollama::Config.new
  end

  def self.configure
    yield(config)
  end
end

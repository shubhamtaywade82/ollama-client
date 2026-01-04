# frozen_string_literal: true

require_relative "ollama/config"
require_relative "ollama/errors"
require_relative "ollama/schema_validator"
require_relative "ollama/client"

module OllamaClient
  def self.config
    @config ||= Ollama::Config.new
  end

  def self.configure
    yield(config)
  end
end


# frozen_string_literal: true

# Optional OpenAI compatibility extension.
#
# Usage:
#   require "ollama_client"
#   require "ollama/openai"
#
# Keeps OpenAI translation semantics out of the default core load path.
require_relative "client/openai_compat"

module Ollama
  class Client
    include OpenAICompat
  end
end

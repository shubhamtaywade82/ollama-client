# frozen_string_literal: true

# OpenAI compatibility extension.
#
# Kept for backwards compatibility with existing `require "ollama/openai"`
# call sites: Ollama::Client already includes OpenAICompat directly
# (lib/ollama/client.rb requires "client/openai_compat" as part of its
# default load path), so client.openai works without this require. This
# file is now a harmless no-op re-require + re-include.
require_relative "client/openai_compat"

module Ollama
  class Client
    include OpenAICompat
  end
end

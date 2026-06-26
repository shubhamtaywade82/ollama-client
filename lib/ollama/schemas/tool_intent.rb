# frozen_string_literal: true

require "json"

module Ollama
  module Schemas
    TOOL_INTENT_PATH = File.join(__dir__, "tool_intent.json")

    TOOL_INTENT = JSON.parse(File.read(TOOL_INTENT_PATH))

    def self.tool_intent
      TOOL_INTENT
    end
  end
end


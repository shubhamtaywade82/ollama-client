# frozen_string_literal: true

module Ollama
  # Typed tool intent parsed from structured generation.
  class ToolIntent
    # @param action [String]
    # @param input [Hash]
    def initialize(action, input = {})
      @action = action
      @input = input
    end

    # @return [String]
    attr_reader :action

    # @return [Hash]
    attr_reader :input
  end
end

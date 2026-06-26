# frozen_string_literal: true

module Ollama
  # Tool intent extraction helper.
  class ToolIntent
    attr_reader :action, :input

    # @param action [String]
    # @param input [Hash]
    def initialize(action, input = {})
      @action = action
      @input = input.is_a?(Hash) ? input : {}
    end
    def finish?
      @action == "finish"
    end
  end
end

# frozen_string_literal: true

module Ollama
  # Wraps a normalized chat response in a Ruby surface that supports
  # traditional attribute access and state checks.
  class ChatResponse
    attr_reader :content, :thinking, :role, :tool_calls, :images, :done, :model

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      content: nil,
      thinking: nil,
      role: "assistant",
      tool_calls: [],
      images: [],
      done: true,
      model: nil
    )
      # rubocop:enable Metrics/ParameterLists
      @content = content
      @thinking = thinking
      @role = role
      @tool_calls = Array(tool_calls)
      @images = Array(images)
      @done = done
      @model = model
    end

    def done?
      done
    end
  end
end

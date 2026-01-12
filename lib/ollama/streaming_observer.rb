# frozen_string_literal: true

module Ollama
  # Presentation-only streaming observer for agent loops.
  # This object must never control tool execution or loop termination.
  class StreamingObserver
    Event = Struct.new(:type, :text, :name, :state, :data, keyword_init: true)

    def initialize(&block)
      @block = block
    end

    def emit(type, text: nil, name: nil, state: nil, data: nil)
      return unless @block

      @block.call(Event.new(type: type, text: text, name: name, state: state, data: data))
    rescue StandardError
      # Observers must never break control flow.
      nil
    end
  end
end

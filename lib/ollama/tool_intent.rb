# frozen_string_literal: true

module Ollama
  ToolIntent = Struct.new(:action, :input, keyword_init: true) do
    def finish?
      action == "finish"
    end
  end
end


# frozen_string_literal: true

module Ollama
  module PromptAdapters
    # Generic adapter — no prompt transformation. Used for all model
    # families not explicitly handled by a dedicated adapter.
    class Generic < Base; end
  end
end

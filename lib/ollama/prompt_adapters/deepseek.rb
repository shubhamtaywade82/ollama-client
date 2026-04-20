# frozen_string_literal: true

module Ollama
  module PromptAdapters
    # DeepSeek adapter. Activates thinking via the think: true API flag.
    class DeepSeek < Base
      def inject_think_flag?
        true
      end
    end
  end
end

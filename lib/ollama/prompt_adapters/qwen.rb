# frozen_string_literal: true

module Ollama
  module PromptAdapters
    # Qwen adapter. Activates thinking via the think: true API flag.
    class Qwen < Base
      def inject_think_flag?
        true
      end
    end
  end
end

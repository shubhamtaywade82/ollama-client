# frozen_string_literal: true

module Ollama
  module PromptAdapters
    # Base prompt adapter — pass-through with no transformation.
    # Subclasses override adapt_messages to apply model-family-specific
    # prompt shaping (e.g. injecting think tags, reordering parts).
    class Base
      attr_reader :profile

      def initialize(profile)
        @profile = profile
      end

      # Transform messages for this model family.
      # @param messages [Array<Hash>]
      # @param think [Boolean, String, nil]
      # @return [Array<Hash>]
      def adapt_messages(messages, think: false)
        messages
      end

      # Whether this adapter injects think: true into the API body.
      # Gemma 4 uses a system-prompt tag instead, so returns false there.
      def inject_think_flag?
        false
      end
    end
  end
end

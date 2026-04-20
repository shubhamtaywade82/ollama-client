# frozen_string_literal: true

module Ollama
  # Strips reasoning/thought content from assistant responses before
  # they are stored in conversation history, preventing thought leakage
  # into subsequent prompt turns.
  #
  # Gemma 4 and other reasoning models require that prior turns contain
  # only the final response — not the thought content.
  #
  # Usage:
  #   sanitizer = HistorySanitizer.for(profile)
  #   sanitizer.add(response, messages: conversation)
  #
  # Trace store example (persist thoughts separately):
  #   traces = []
  #   sanitizer = HistorySanitizer.new(policy: :exclude_thoughts, trace_store: traces)
  class HistorySanitizer
    # @param policy [:exclude_thoughts, :none]
    # @param trace_store [Array, nil] optional sink for reasoning traces
    def initialize(policy: :exclude_thoughts, trace_store: nil)
      @policy = policy
      @trace_store = trace_store
    end

    # Build a sanitizer appropriate for a model profile.
    # @param profile [Ollama::ModelProfile]
    # @param trace_store [Array, nil]
    # @return [HistorySanitizer]
    def self.for(profile, trace_store: nil)
      new(policy: profile.history_policy, trace_store: trace_store)
    end

    # Append a response to the messages array, sanitized per policy.
    # Returns the appended message hash.
    # @param response [Ollama::Response]
    # @param messages [Array<Hash>]
    # @return [Hash] the appended message
    def add(response, messages:)
      case @policy
      when :exclude_thoughts
        store_trace(response)
      end
      msg = { role: "assistant", content: response.content.to_s }
      messages << msg
      msg
    end

    private

    def store_trace(response)
      return unless @trace_store
      return if response.message&.thinking.to_s.empty?

      @trace_store << {
        model: response.model,
        thinking: response.message.thinking,
        final: response.content
      }
    end
  end
end

# frozen_string_literal: true

module Ollama
  # A typed event emitted during a streaming chat response.
  # Provides clean separation between reasoning, answer tokens, tool calls,
  # and terminal events — enabling UI rendering, JSONL tracing, and agent
  # orchestration without mixing reasoning into the final answer.
  #
  # Event types:
  #   :thought_start   — reasoning block begins
  #   :thought_delta   — incremental reasoning token
  #   :thought_end     — reasoning block complete
  #   :answer_delta    — incremental final-answer token
  #   :tool_call_start — tool call ready (data = ToolCall hash)
  #   :tool_call_delta — incremental tool call token (partial streaming)
  #   :complete        — stream finished (data = Ollama::Response)
  #   :error           — stream error (data = exception)
  StreamEvent = Struct.new(:type, :data, :model, keyword_init: true) do
    TYPES = %i[
      thought_start thought_delta thought_end
      answer_delta
      tool_call_start tool_call_delta
      complete error
    ].freeze

    def thought?   = %i[thought_start thought_delta thought_end].include?(type)
    def answer?    = type == :answer_delta
    def tool_call? = %i[tool_call_start tool_call_delta].include?(type)
    def terminal?  = %i[complete error].include?(type)

    # Serialize to a JSONL line for trace logging.
    def to_jsonl
      require "json"
      data_val = data.respond_to?(:to_h) ? data.to_h : data
      JSON.generate({ type: type, model: model, data: data_val })
    end
  end
end

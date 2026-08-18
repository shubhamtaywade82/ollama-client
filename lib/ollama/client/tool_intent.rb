# frozen_string_literal: true

require_relative "../tool_intent"
require_relative "../schemas/tool_intent"

module Ollama
  class Client
    # Tool intent extraction for agent decision pipelines.
    module ToolIntent
      # Extract a structured tool intent from the model using the client's
      # internal schema validators.
      #
      # @param prompt [String] Conversation turn/hint text.
      # @param tools [Array<Hash>] Available tool definitions.
      # @param model [String, nil] Optional model override.
      # @param schema [Hash, nil] Optional schema override.
      # @return [Ollama::ToolIntent, nil] Parsed intent or nil when absent.
      def generate_tool_intent(prompt:, tools:, model: nil, schema: nil)
        intent_schema = schema || Ollama::Schemas.tool_intent

        parsed = generate(
          prompt: prompt,
          schema: intent_schema,
          model: model,
          tools: tools,
          strict: true
        )

        return nil unless parsed.is_a?(Hash)

        input = parsed["input"].is_a?(Hash) ? parsed["input"] : {}
        Ollama::ToolIntent.new(parsed["action"].to_s, input)
      rescue InvalidJSONError, RetryExhaustedError
        nil
      end
    end
  end
end

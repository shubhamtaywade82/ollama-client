# frozen_string_literal: true

require "json"
require_relative "messages"

module Ollama
  module Agent
    # Stateless planner-style agent using /api/generate.
    #
    # Intended for planning, classification, routing, and deterministic structured outputs.
    class Planner
      ANY_JSON_SCHEMA = {
        "anyOf" => [
          { "type" => "object", "additionalProperties" => true },
          { "type" => "array" },
          { "type" => "string" },
          { "type" => "number" },
          { "type" => "integer" },
          { "type" => "boolean" },
          { "type" => "null" }
        ]
      }.freeze

      def initialize(client, system_prompt: nil)
        @client = client
        @system_prompt = system_prompt
      end

      # @param prompt [String]
      # @param context [Hash, nil]
      # @param schema [Hash, nil]
      # @param system_prompt [String, nil] Optional system prompt override for this call
      # @return [Object] Parsed JSON (Hash/Array/String/Number/Boolean/Nil)
      def run(prompt:, context: nil, schema: nil, system_prompt: nil)
        effective_system = system_prompt || @system_prompt
        full_prompt = prompt.to_s

        full_prompt = "#{effective_system}\n\n#{full_prompt}" if effective_system && !effective_system.empty?

        if context && !context.empty?
          full_prompt = "#{full_prompt}\n\nContext (JSON):\n#{JSON.pretty_generate(context)}"
        end

        @client.generate(
          prompt: full_prompt,
          schema: schema || ANY_JSON_SCHEMA,
          strict: true
        )
      end
    end
  end
end

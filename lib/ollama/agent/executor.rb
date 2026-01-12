# frozen_string_literal: true

require "json"
require_relative "messages"

module Ollama
  module Agent
    # Stateful executor-style agent using /api/chat + tool-calling loop.
    #
    # The LLM never executes tools. It can only request tool calls; this class
    # executes Ruby callables and feeds results back as role: "tool" messages.
    class Executor
      attr_reader :messages

      def initialize(client, tools:, max_steps: 20, stream: nil)
        @client = client
        @tools = tools || {}
        @max_steps = max_steps
        @stream = stream
        @messages = []
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
      def run(system:, user:)
        @messages = [
          Messages.system(system),
          Messages.user(user)
        ]

        last_assistant_content = nil

        @max_steps.times do
          @stream&.emit(:state, state: :assistant_streaming)

          response =
            if @stream
              @client.chat_raw(
                messages: @messages,
                tools: tool_definitions,
                allow_chat: true,
                stream: true
              ) do |chunk|
                delta = chunk.dig("message", "content")
                @stream.emit(:token, text: delta.to_s) if delta && !delta.to_s.empty?

                calls = chunk.dig("message", "tool_calls")
                if calls.is_a?(Array)
                  calls.each do |call|
                    name = dig(call, %w[function name]) || call["name"]
                    @stream.emit(:tool_call_detected, name: name, data: call) if name
                  end
                end
              end
            else
              @client.chat_raw(messages: @messages, tools: tool_definitions, allow_chat: true)
            end

          message = response["message"] || {}
          content = message["content"]
          tool_calls = message["tool_calls"]

          # Preserve the assistant turn in history (including tool_calls if present).
          @messages << Messages.assistant(content.to_s, tool_calls: tool_calls) if content || tool_calls
          last_assistant_content = content if content && !content.empty?

          break if tool_calls.nil? || tool_calls.empty?

          tool_calls.each do |call|
            name = dig(call, %w[function name]) || call["name"]
            raise Ollama::Error, "Tool call missing function name: #{call.inspect}" if name.nil? || name.empty?

            args = dig(call, %w[function arguments])
            args_hash = normalize_arguments(args)

            callable = @tools[name]
            raise Ollama::Error, "Tool '#{name}' not found. Available: #{@tools.keys.sort.join(", ")}" unless callable

            @stream&.emit(:state, state: :tool_executing)
            result = invoke_tool(callable, args_hash)
            tool_content = encode_tool_result(result)

            tool_call_id = call["id"] || call["tool_call_id"]
            @messages << Messages.tool(content: tool_content, name: name, tool_call_id: tool_call_id)
            @stream&.emit(:state, state: :tool_result_injected)
          end
        end

        if last_assistant_content.nil?
          raise Ollama::Error,
                "Executor exceeded max_steps=#{@max_steps} (possible infinite tool loop)"
        end

        @stream&.emit(:final, text: last_assistant_content.to_s)
        last_assistant_content
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength

      private

      def tool_definitions
        @tools.keys.sort.map do |name|
          {
            type: "function",
            function: {
              name: name,
              description: "Tool: #{name}",
              parameters: {
                "type" => "object",
                "additionalProperties" => true
              }
            }
          }
        end
      end

      def dig(obj, path)
        cur = obj
        path.each do |k|
          return nil unless cur.is_a?(Hash)

          cur = cur[k] || cur[k.to_sym]
        end
        cur
      end

      def normalize_arguments(args)
        return {} if args.nil? || args == ""
        return args if args.is_a?(Hash)

        if args.is_a?(String)
          JSON.parse(args)
        else
          {}
        end
      rescue JSON::ParserError => e
        raise Ollama::InvalidJSONError, "Failed to parse tool arguments JSON: #{e.message}. Arguments: #{args.inspect}"
      end

      def invoke_tool(callable, args_hash)
        sym_args = args_hash.transform_keys { |k| k.to_s.to_sym }

        # Prefer keyword invocation (common for Ruby tools), fall back to a single hash.
        callable.call(**sym_args)
      rescue ArgumentError
        callable.call(args_hash)
      end

      def encode_tool_result(result)
        return result if result.is_a?(String)

        JSON.generate(result)
      rescue JSON::GeneratorError
        result.to_s
      end
    end
  end
end

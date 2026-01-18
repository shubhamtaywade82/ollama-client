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

            tool_entry = @tools[name]
            raise Ollama::Error, "Tool '#{name}' not found. Available: #{@tools.keys.sort.join(", ")}" unless tool_entry

            # Extract callable from tool entry
            callable = extract_callable(tool_entry)
            raise Ollama::Error, "Tool '#{name}' has no associated callable" unless callable

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
          tool_entry = @tools[name]

          # Support both explicit Tool objects and callables
          # Tool objects are schema definitions only
          if tool_entry.is_a?(Ollama::Tool)
            tool_entry.to_h
          elsif tool_entry.is_a?(Hash) && tool_entry[:tool].is_a?(Ollama::Tool)
            # Format: { tool: Tool, callable: proc }
            tool_entry[:tool].to_h
          else
            # Auto-infer from callable signature (default)
            callable = tool_entry.is_a?(Hash) ? tool_entry[:callable] : tool_entry
            parameters = infer_parameters(callable)
            {
              type: "function",
              function: {
                name: name,
                description: "Tool: #{name}",
                parameters: parameters
              }
            }
          end
        end
      end

      def infer_parameters(callable)
        return { "type" => "object", "additionalProperties" => true } unless callable.respond_to?(:parameters)

        params = callable.parameters
        return { "type" => "object", "additionalProperties" => true } if params.empty?

        properties = {}
        required = []

        params.each do |type, name|
          next unless name # Skip anonymous parameters

          param_name = name.to_s
          properties[param_name] = { "type" => "string", "description" => "Parameter: #{param_name}" }

          # Required if it's a required keyword argument (:keyreq) or required positional (:req)
          required << param_name if %i[keyreq req].include?(type)
        end

        schema = { "type" => "object" }
        schema["properties"] = properties unless properties.empty?
        schema["required"] = required unless required.empty?
        schema["additionalProperties"] = false if properties.any?

        schema
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
        sym_args = normalize_parameter_names(args_hash)
        keyword_result = call_with_keywords(callable, sym_args)
        return keyword_result[:value] if keyword_result[:success]

        call_with_positional(callable, args_hash)
      end

      def normalize_parameter_names(args_hash)
        args_hash.transform_keys { |k| k.to_s.to_sym }
      end

      def apply_parameter_aliases(args, callable)
        return args unless callable.respond_to?(:parameters)

        param_names = callable.parameters.map { |_type, name| name }
        aliased = args.dup

        # Common aliases: directory -> path, file -> path, filename -> path
        if param_names.include?(:path) && !aliased.key?(:path)
          if aliased.key?(:directory)
            aliased[:path] = aliased.delete(:directory)
          elsif aliased.key?(:file)
            aliased[:path] = aliased.delete(:file)
          elsif aliased.key?(:filename)
            aliased[:path] = aliased.delete(:filename)
          end
        end

        aliased
      end

      def call_with_keywords(callable, sym_args)
        { success: true, value: callable.call(**sym_args) }
      rescue ArgumentError => e
        return { success: false } unless missing_keyword_error?(e)

        aliased_args = apply_parameter_aliases(sym_args, callable)
        return { success: false } if aliased_args == sym_args

        begin
          { success: true, value: callable.call(**aliased_args) }
        rescue ArgumentError
          { success: false }
        end
      end

      def call_with_positional(callable, args_hash)
        callable.call(args_hash)
      rescue ArgumentError => e
        raise ArgumentError,
              "Tool invocation failed: #{e.message}. Arguments provided: #{args_hash.inspect}. " \
              "Ensure the tool call includes all required parameters."
      end

      def missing_keyword_error?(error)
        error.message.include?("required keyword") || error.message.include?("missing keyword")
      end

      def encode_tool_result(result)
        return result if result.is_a?(String)

        JSON.generate(result)
      rescue JSON::GeneratorError
        result.to_s
      end

      def extract_callable(tool_entry)
        case tool_entry
        when Proc, Method
          tool_entry
        when Hash
          tool_entry[:callable] || tool_entry["callable"]
        end
      end
    end
  end
end

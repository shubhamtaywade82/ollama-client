# frozen_string_literal: true

module Ollama
  class Client
    # Consumes an NDJSON /api/chat stream, aggregates message fields, and dispatches hooks.
    class ChatStreamProcessor
      def initialize(hooks)
        @hooks = hooks
      end

      def call(res)
        full_content  = +""
        full_thinking = +""
        full_logprobs = []
        last_data = nil
        thinking_started = false

        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          while (newline_idx = buffer.index("\n"))
            line = buffer.slice!(0, newline_idx + 1).strip
            next if line.empty?

            begin
              obj = JSON.parse(line)
              thinking_started, last_data = process_chunk(
                obj, full_content, full_thinking, full_logprobs, last_data, thinking_started
              )
            rescue JSON::ParserError
              # Ignore malformed stream chunks
            end
          end
        end

        build_result(last_data, full_content, full_thinking, full_logprobs)
      end

      private

      def build_result(last_data, full_content, full_thinking, full_logprobs)
        result = last_data || {}
        result["message"] ||= {}
        result["message"]["content"] = full_content
        result["message"]["thinking"] = full_thinking unless full_thinking.empty?
        result["message"]["role"] ||= "assistant"
        result["logprobs"] = full_logprobs unless full_logprobs.empty?
        result
      end

      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      def process_chunk(obj, full_content, full_thinking, full_logprobs, last_data, thinking_started)
        if obj["error"]
          error = StreamError.new(obj["error"])
          @hooks[:on_error]&.call(error)
          raise error
        end

        if obj["message"]
          content = obj["message"]["content"]
          thinking = obj["message"]["thinking"]

          if thinking && !thinking.empty?
            unless thinking_started
              @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_start, data: nil))
              thinking_started = true
            end
            full_thinking << thinking
            @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_delta, data: thinking))
          end

          if content && !content.empty?
            if thinking_started && !full_thinking.empty?
              @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_end, data: nil))
              thinking_started = false
            end
            full_content << content
            if @hooks[:on_token]&.arity == 2
              @hooks[:on_token].call(content, obj["logprobs"])
            else
              @hooks[:on_token]&.call(content)
            end
          end

          full_logprobs.concat(obj["logprobs"]) if obj["logprobs"]
        end

        if obj["done"]
          Array(obj.dig("message", "tool_calls")).each { |tc| @hooks[:on_tool_call]&.call(tc) }

          @hooks[:on_complete]&.call
          return [thinking_started, obj]
        end

        [thinking_started, last_data]
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    end
  end
end

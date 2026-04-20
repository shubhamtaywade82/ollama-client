# frozen_string_literal: true

module Ollama
  class Client
    # Consumes an NDJSON /api/chat stream, aggregates message fields, and dispatches hooks.
    # Line buffering matches Ollama::GenerateStreamHandler so both NDJSON parsers stay parallel.
    class ChatStreamProcessor
      def initialize(hooks)
        @hooks = hooks
      end

      def call(res)
        reset_accumulators!

        buffer = +""
        res.read_body { |chunk| drain_chunk(buffer, chunk) }

        build_result
      end

      private

      def reset_accumulators!
        @full_content = +""
        @full_thinking = +""
        @full_logprobs = []
        @last_data = nil
        @thinking_started = false
      end

      def drain_chunk(buffer, chunk)
        buffer << chunk
        extract_lines(buffer)
      end

      def extract_lines(buffer)
        while (newline_idx = buffer.index("\n"))
          line = buffer.slice!(0, newline_idx + 1).strip
          handle_line(line) unless line.empty?
        end
      end

      def handle_line(line)
        handle_event(JSON.parse(line))
      rescue JSON::ParserError
        nil
      end

      def build_result
        result = @last_data || {}
        result["message"] ||= {}
        result["message"]["content"] = @full_content
        result["message"]["thinking"] = @full_thinking unless @full_thinking.empty?
        result["message"]["role"] ||= "assistant"
        result["logprobs"] = @full_logprobs unless @full_logprobs.empty?
        result
      end

      def handle_event(obj)
        if obj["error"]
          error = StreamError.new(obj["error"])
          @hooks[:on_error]&.call(error)
          raise error
        end

        if obj["message"]
          content = obj["message"]["content"]
          thinking = obj["message"]["thinking"]

          if thinking && !thinking.empty?
            start_thought_block unless @thinking_started
            @full_thinking << thinking
            @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_delta, data: thinking))
          end

          if content && !content.empty?
            end_thought_block_if_needed
            @full_content << content
            emit_token(content, obj["logprobs"])
          end

          @full_logprobs.concat(obj["logprobs"]) if obj["logprobs"]
        end

        return unless obj["done"]

        Array(obj.dig("message", "tool_calls")).each { |tc| @hooks[:on_tool_call]&.call(tc) }

        @hooks[:on_complete]&.call
        @last_data = obj
      end

      def start_thought_block
        @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_start, data: nil))
        @thinking_started = true
      end

      def end_thought_block_if_needed
        return unless @thinking_started && !@full_thinking.empty?

        @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_end, data: nil))
        @thinking_started = false
      end

      def emit_token(content, logprobs)
        if @hooks[:on_token]&.arity == 2
          @hooks[:on_token].call(content, logprobs)
        else
          @hooks[:on_token]&.call(content)
        end
      end
    end
  end
end

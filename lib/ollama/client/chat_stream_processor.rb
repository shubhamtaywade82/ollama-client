# frozen_string_literal: true

module Ollama
  class Client
    # Consumes an NDJSON /api/chat stream, aggregates message fields, and dispatches hooks.
    # Line buffering matches Ollama::GenerateStreamHandler so both NDJSON parsers stay parallel.
    class ChatStreamProcessor
      # Convenience class method to process a stream.
      # @param res [Net::HTTPResponse]
      # @param hooks [Hash]
      # @param provider [Ollama::Providers::Base]
      # @return [Hash] the aggregated result
      def self.call(res, hooks, provider: nil)
        new(hooks, provider: provider).call(res)
      end

      # @param hooks [Hash]
      # @param provider [Ollama::Providers::Base]
      def initialize(hooks, provider: nil)
        @hooks = hooks
        @provider = provider
      end

      # @param res [Net::HTTPResponse]
      # @return [Hash] the aggregated result
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
        # OpenAI SSE uses "data: " prefix and ends with "data: [DONE]"
        return if line == "data: [DONE]"

        json_text = line.start_with?("data: ") ? line.sub(/^data: /, "") : line
        handle_event(JSON.parse(json_text))
      rescue JSON::ParserError => e
        @hooks[:on_error]&.call(MalformedStreamError.new("Failed to parse JSON line: #{e.message}"))
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
        # Normalize event if it's from OpenAI
        obj = normalize_openai_delta(obj) if @provider.is_a?(Providers::OpenAI)

        handle_error_event(obj) if obj["error"]
        process_message_field(obj) if obj["message"]
        finalize_stream_if_done(obj) if obj["done"]
      end

      def handle_error_event(obj)
        error = StreamError.new(obj["error"])
        @hooks[:on_error]&.call(error)
        raise error
      end

      def process_message_field(obj)
        msg = obj["message"]
        content = msg["content"]
        thinking = msg["thinking"]

        process_thinking(thinking) if thinking && !thinking.empty?
        process_content(content, obj["logprobs"]) if content && !content.empty?

        @full_logprobs.concat(obj["logprobs"]) if obj["logprobs"]
      end

      def process_thinking(thinking)
        start_thought_block unless @thinking_started
        @full_thinking << thinking
        @hooks[:on_thought]&.call(StreamEvent.new(type: :thought_delta, data: thinking))
      end

      def process_content(content, logprobs)
        end_thought_block_if_needed
        @full_content << content
        emit_token(content, logprobs)
      end

      def finalize_stream_if_done(obj)
        Array(obj.dig("message", "tool_calls")).each { |tc| @hooks[:on_tool_call]&.call(tc) }

        @hooks[:on_complete]&.call
        @last_data = obj
      end

      def normalize_openai_delta(obj)
        return obj unless obj.key?("choices")

        choice = obj["choices"][0]
        delta = choice["delta"] || {}

        {
          "model" => obj["model"],
          "message" => {
            "role" => delta["role"],
            "content" => delta["content"],
            "tool_calls" => translate_openai_tool_calls(delta["tool_calls"])
          },
          "done" => !choice["finish_reason"].nil?,
          "done_reason" => choice["finish_reason"]
        }
      end

      def translate_openai_tool_calls(openai_tool_calls)
        return nil unless openai_tool_calls

        openai_tool_calls.map do |tc|
          {
            "function" => {
              "name" => tc.dig("function", "name"),
              "arguments" => tc.dig("function", "arguments")
            }
          }
        end
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

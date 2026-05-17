# frozen_string_literal: true

require_relative "errors"

module Ollama
  # Consumes NDJSON lines from an Ollama /api/generate streaming HTTP body.
  class GenerateStreamHandler
    def self.call(response, hooks, accumulator, provider: nil)
      new(response, hooks, accumulator, provider: provider).call
    end

    def initialize(response, hooks, accumulator, provider: nil)
      @response = response
      @hooks = hooks
      @accumulator = accumulator
      @provider = provider
    end

    def call
      buffer = +""
      @response.read_body { |chunk| drain_chunk(buffer, chunk) }
    end

    private

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
    rescue JSON::ParserError
      nil
    end

    def handle_event(obj)
      # Normalize event if it's from OpenAI
      obj = normalize_openai_delta(obj) if @provider.is_a?(Providers::OpenAI)

      return emit_stream_error(obj["error"]) if obj["error"]

      append_token(obj["response"]) if obj["response"]
      @hooks[:on_complete]&.call if obj["done"]
    end

    def normalize_openai_delta(obj)
      return obj unless obj.key?("choices")

      choice = obj["choices"][0]
      {
        "model" => obj["model"],
        "response" => choice["text"],
        "done" => choice["finish_reason"] != nil
      }
    end

    def emit_stream_error(message)
      error = StreamError.new(message)
      @hooks[:on_error]&.call(error)
      raise error
    end

    def append_token(token)
      @accumulator << token
      @hooks[:on_token]&.call(token)
    end
  end
end

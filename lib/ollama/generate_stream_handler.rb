# frozen_string_literal: true

require_relative "errors"

module Ollama
  # Consumes NDJSON lines from an Ollama /api/generate streaming HTTP body.
  class GenerateStreamHandler
    def self.call(response, hooks, accumulator)
      new(response, hooks, accumulator).call
    end

    def initialize(response, hooks, accumulator)
      @response = response
      @hooks = hooks
      @accumulator = accumulator
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
      handle_event(JSON.parse(line))
    rescue JSON::ParserError
      nil
    end

    def handle_event(obj)
      return emit_stream_error(obj["error"]) if obj["error"]

      append_token(obj["response"]) if obj["response"]
      @hooks[:on_complete]&.call if obj["done"]
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

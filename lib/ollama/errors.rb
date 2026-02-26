# frozen_string_literal: true

module Ollama
  class Error < StandardError; end
  class TimeoutError < Error; end
  class InvalidJSONError < Error; end
  class SchemaViolationError < Error; end
  class RetryExhaustedError < Error; end
  class ChatNotAllowedError < Error; end
  class StreamError < Error; end
  class ThinkingFormatError < Error; end
  class UnsupportedThinkingModel < Error; end

  # HTTP error with retry logic
  class HTTPError < Error
    attr_reader :status_code

    def initialize(message, status_code = nil)
      super(message)
      @status_code = status_code
    end

    def retryable?
      # Explicit retry policy:
      # - Retry: 408 (Request Timeout), 429 (Too Many Requests),
      #   500 (Internal Server Error), 502 (Bad Gateway), 503 (Service Unavailable)
      # - Never retry: 400-407, 409-428, 430-499 (client errors)
      # - Never retry: 501, 504-599 (other server errors - may indicate permanent issues)
      return true if @status_code.nil? # Unknown status - retry for safety
      return true if [408, 429, 500, 502, 503].include?(@status_code)

      false
    end
  end

  # Specific error for 404 Not Found responses
  class NotFoundError < HTTPError
    attr_reader :requested_model, :suggestions

    def initialize(message = "Resource not found", requested_model: nil, suggestions: [])
      super("HTTP 404: #{message}", 404)
      @requested_model = requested_model
      @suggestions = suggestions
    end

    def retryable?
      false
    end

    def to_s
      msg = super
      return msg unless @requested_model && !@suggestions.empty?

      suggestion_text = @suggestions.map { |m| "  - #{m}" }.join("\n")
      "#{msg}\n\nModel '#{@requested_model}' not found. Did you mean one of these?\n#{suggestion_text}"
    end
  end
end

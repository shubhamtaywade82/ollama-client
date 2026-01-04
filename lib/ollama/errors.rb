# frozen_string_literal: true

module Ollama
  class Error < StandardError; end
  class TimeoutError < Error; end
  class InvalidJSONError < Error; end
  class SchemaViolationError < Error; end
  class RetryExhaustedError < Error; end

  # HTTP error with retry logic
  class HTTPError < Error
    attr_reader :status_code

    def initialize(message, status_code = nil)
      super(message)
      @status_code = status_code
    end

    def retryable?
      # Retry on server errors (5xx) and some client errors (408, 429)
      return true if @status_code.nil?
      return true if @status_code >= 500
      return true if [408, 429].include?(@status_code)

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

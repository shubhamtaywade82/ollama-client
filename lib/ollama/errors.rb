# frozen_string_literal: true

module Ollama
  class Error < StandardError; end
  class TimeoutError < Error; end
  class InvalidJSONError < Error; end
  class SchemaViolationError < Error; end
  class RetryExhaustedError < Error; end
end

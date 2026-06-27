# frozen_string_literal: true

require "json"
require_relative "errors"

module Ollama
  # Shared HTTP error handling for all API clients
  module HttpErrorHandler
    # Handle HTTP error response and raise appropriate Ollama error
    # @param response [Net::HTTPResponse] HTTP response
    # @param requested_model [String, nil] Model name for error context
    # @raise [Ollama::Error] Appropriate error subclass
    def handle_http_error(response, requested_model: nil)
      status_code = response.code.to_i
      error_message = extract_error_message(response) || response.message

      case status_code
      when 401
        raise UnauthorizedError.new("HTTP 401: #{error_message}", 401)
      when 404
        raise NotFoundError.new(error_message, requested_model: requested_model)
      when 503
        raise ModelUnavailableError.new("HTTP 503: #{error_message}", 503)
      else
        raise HTTPError.new("HTTP #{status_code}: #{error_message}", status_code)
      end
    end

    # Extract error message from response body
    # @param response [Net::HTTPResponse] HTTP response
    # @return [String, nil] Error message or nil
    def extract_error_message(response)
      body = response.body
      return nil if body.nil? || body.empty?

      parsed = JSON.parse(body)
      parsed["error"] if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end

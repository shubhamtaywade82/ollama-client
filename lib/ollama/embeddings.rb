# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"

module Ollama
  # Embeddings API helper for semantic search and RAG in agents
  #
  # This is a helper module used internally by Client.
  # Use client.embeddings.embed() instead of instantiating this directly.
  class Embeddings
    def initialize(config)
      @config = config
    end

    # Generate embeddings for text input(s)
    #
    # @param model [String] Embedding model name (e.g., "all-minilm")
    # @param input [String, Array<String>] Single text or array of texts
    # @return [Array<Float>, Array<Array<Float>>] Embedding vector(s)
    def embed(model:, input:)
      # Use /api/embed (not /api/embeddings) - the working endpoint
      uri = URI("#{@config.base_url}/api/embed")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"

      body = {
        model: model,
        input: input
      }

      req.body = body.to_json

      res = Net::HTTP.start(
        uri.hostname,
        uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      handle_http_error(res, requested_model: model) unless res.is_a?(Net::HTTPSuccess)

      response_body = JSON.parse(res.body)
      # /api/embed returns "embeddings" (plural) as array of arrays
      embeddings = response_body["embeddings"] || response_body["embedding"]

      validate_embedding_response!(embeddings, response_body, model)

      format_embedding_result(embeddings, input)
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse embeddings response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    private

    def validate_embedding_response!(embeddings, response_body, model)
      if embeddings.nil?
        keys = response_body.keys.join(", ")
        response_preview = response_body.inspect[0..200]
        raise Error, "Embeddings not found in response. Response keys: #{keys}. " \
                     "Full response: #{response_preview}"
      end

      # Handle both formats: array of arrays [[...]] or single array [...]
      # Check if it's empty or contains empty arrays
      if embeddings.is_a?(Array) && (embeddings.empty? || (embeddings.first.is_a?(Array) && embeddings.first.empty?))
        error_msg = build_empty_embedding_error_message(model, response_body)
        raise Error, error_msg
      end

      nil
    end

    def build_empty_embedding_error_message(model, response_body)
      curl_command = "curl -X POST http://localhost:11434/api/embed " \
                     "-d '{\"model\":\"#{model}\",\"input\":\"test\"}'"
      response_preview = response_body.inspect[0..300]

      # Check for error messages in response
      error_hint = ""
      if response_body.is_a?(Hash)
        if response_body.key?("error")
          error_hint = "\n  Error from Ollama: #{response_body["error"]}"
        elsif response_body.key?("message")
          error_hint = "\n  Message from Ollama: #{response_body["message"]}"
        end
      end

      "Empty embedding returned. This usually means:\n  " \
        "1. The model may not be properly loaded - try: ollama pull #{model}\n  " \
        "2. The model file may be corrupted - try: ollama rm #{model} && ollama pull #{model}\n  " \
        "3. The model may not support embeddings - verify it's an embedding model\n  " \
        "4. Check if the model is working: #{curl_command}#{error_hint}\n" \
        "Response: #{response_preview}"
    end

    def format_embedding_result(embeddings, input)
      # /api/embed returns "embeddings" as array of arrays [[...]]
      # For single input, it's [[...]], for multiple inputs it's [[...], [...], ...]
      if embeddings.is_a?(Array) && embeddings.first.is_a?(Array)
        # Already in correct format (array of arrays)
        # For single input, return first embedding array
        # For multiple inputs, return all embedding arrays
        input.is_a?(Array) ? embeddings : embeddings.first
      else
        # Fallback: single array format (shouldn't happen with /api/embed)
        input.is_a?(Array) ? [embeddings] : embeddings
      end
    end

    def handle_http_error(res, requested_model: nil)
      status_code = res.code.to_i
      raise NotFoundError.new(res.message, requested_model: requested_model) if status_code == 404

      raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
    end
  end
end

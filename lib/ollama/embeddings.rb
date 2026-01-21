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
      uri = URI("#{@config.base_url}/api/embeddings")
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
      embedding = response_body["embedding"]

      validate_embedding_response!(embedding, response_body, model)

      format_embedding_result(embedding, input)
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse embeddings response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    private

    def validate_embedding_response!(embedding, response_body, model)
      if embedding.nil?
        keys = response_body.keys.join(", ")
        response_preview = response_body.inspect[0..200]
        raise Error, "Embedding not found in response. Response keys: #{keys}. " \
                     "Full response: #{response_preview}"
      end

      return unless embedding.is_a?(Array) && embedding.empty?

      error_msg = build_empty_embedding_error_message(model, response_body)
      raise Error, error_msg
    end

    def build_empty_embedding_error_message(model, response_body)
      curl_command = "curl http://localhost:11434/api/embeddings " \
                     "-d '{\"model\":\"#{model}\",\"input\":\"test\"}'"
      response_preview = response_body.inspect[0..300]

      "Empty embedding returned. This usually means:\n  " \
        "1. The model may not be properly loaded - try: ollama pull #{model}\n  " \
        "2. The model may not support embeddings - verify it's an embedding model\n  " \
        "3. Check if the model is working: #{curl_command}\n" \
        "Response: #{response_preview}"
    end

    def format_embedding_result(embedding, input)
      return embedding unless input.is_a?(Array)

      # Ollama returns single embedding array even for multiple inputs
      # We need to check the response structure
      if embedding.is_a?(Array) && embedding.first.is_a?(Array)
        embedding
      else
        # Single embedding returned, wrap it
        [embedding]
      end
    end

    def handle_http_error(res, requested_model: nil)
      status_code = res.code.to_i
      raise NotFoundError.new(res.message, requested_model: requested_model) if status_code == 404

      raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
    end
  end
end

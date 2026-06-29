# frozen_string_literal: true

require_relative "base"

module Ollama
  module Serializers
    # Serializes embeddings requests
    class Embeddings < Base
      def call(request)
        body = build_embeddings_body(request)
        Transport::Request.new(
          method: http_method(request),
          uri: build_uri(request, request.path),
          headers: build_headers(request),
          body: body.to_json,
          stream: false,
          timeout: request.metadata[:timeout] || 120
        )
      end

      private

      def build_embeddings_body(request)
        body = {
          model: request.model,
          input: request.prompt
        }

        body[:options] = request.options if request.options&.any?
        body[:keep_alive] = request.keep_alive if request.keep_alive

        body.compact
      end
    end
  end
end

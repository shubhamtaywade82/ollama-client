# frozen_string_literal: true

require "uri"

module Ollama
  module Providers
    # Native Ollama API provider
    class Ollama < Base
      def chat_endpoint
        URI("#{config.base_url}/api/chat")
      end

      def generate_endpoint
        URI("#{config.base_url}/api/generate")
      end

      def embeddings_endpoint
        URI("#{config.base_url}/api/embed")
      end

      def models_endpoint
        URI("#{config.base_url}/api/tags")
      end

      def format_chat_request(params)
        params
      end

      def format_generate_request(params)
        params
      end

      def format_embeddings_request(params)
        params
      end

      def normalize_chat_response(response_data)
        response_data # Native Ollama format matches Ollama::Response
      end

      def normalize_generate_response(response_data)
        response_data # Native Ollama format
      end

      def normalize_embeddings_response(response_data)
        response_data
      end

      def normalize_models_response(response_data)
        response_data
      end
    end
  end
end

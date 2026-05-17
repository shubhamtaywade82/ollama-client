# frozen_string_literal: true

module Ollama
  module Providers
    # Base class for API providers (Ollama, OpenAI, etc.)
    class Base
      attr_reader :config, :transport

      def initialize(config, transport)
        @config = config
        @transport = transport
      end

      # @abstract
      def chat_endpoint
        raise NotImplementedError
      end

      # @abstract
      def generate_endpoint
        raise NotImplementedError
      end

      # @abstract
      def embeddings_endpoint
        raise NotImplementedError
      end

      # @abstract
      def models_endpoint
        raise NotImplementedError
      end

      # @abstract
      def format_chat_request(params)
        raise NotImplementedError
      end

      # @abstract
      def format_generate_request(params)
        raise NotImplementedError
      end

      # @abstract
      def format_embeddings_request(params)
        raise NotImplementedError
      end

      # @abstract
      def normalize_chat_response(response_data)
        raise NotImplementedError
      end

      # @abstract
      def normalize_generate_response(response_data)
        raise NotImplementedError
      end

      # @abstract
      def normalize_embeddings_response(response_data)
        raise NotImplementedError
      end

      # @abstract
      def normalize_models_response(response_data)
        raise NotImplementedError
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base"

require_relative "../responses/embeddings"

module Ollama
  module Parsers
    # Parses embeddings responses
    class Embeddings < Base
      def initialize(provider: nil)
        super()
        @provider = provider
      end

      def call(transport_response)
        data = json(transport_response)
        data = @provider.normalize_embeddings_response(data) if @provider.respond_to?(:normalize_embeddings_response)
        Responses::Embeddings.new(data)
      end
    end
  end
end

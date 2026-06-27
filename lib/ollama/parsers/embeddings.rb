# frozen_string_literal: true

require_relative "base"

module Ollama
  module Parsers
    # Parses embeddings responses
    class Embeddings < Base
      def call(transport_response)
        data = json(transport_response)
        data["embeddings"] || data[:embeddings] || []
      end
    end
  end
end

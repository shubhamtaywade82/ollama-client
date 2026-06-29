# frozen_string_literal: true

require_relative "base"

module Ollama
  module Responses
    # Typed response wrapper for embeddings endpoint
    class Embeddings < Base
      def embeddings
        @data["embeddings"] || @data[:embeddings]
      end
    end
  end
end

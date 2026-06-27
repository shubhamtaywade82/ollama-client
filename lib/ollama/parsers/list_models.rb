# frozen_string_literal: true

require_relative "base"

module Ollama
  module Parsers
    # Parses list_models responses
    class ListModels < Base
      def call(transport_response)
        data = json(transport_response)
        data["models"] || data[:models] || []
      end
    end
  end
end

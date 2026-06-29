# frozen_string_literal: true

require_relative "base"

module Ollama
  module Parsers
    # Parses model management responses (create, delete, copy, pull, push)
    class ModelManagement < Base
      def call(transport_response)
        data = json(transport_response)
        # These endpoints return status objects
        { status: data["status"] || data[:status], body: data }
      end
    end
  end
end

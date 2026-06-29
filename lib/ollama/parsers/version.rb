# frozen_string_literal: true

require_relative "base"

module Ollama
  module Parsers
    # Parses version responses
    class Version < Base
      def call(transport_response)
        data = json(transport_response)
        data["version"] || data[:version]
      end
    end
  end
end

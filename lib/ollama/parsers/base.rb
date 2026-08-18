# frozen_string_literal: true

module Ollama
  module Parsers
    # Base parser contract - converts Transport::Response to domain Response
    class Base
      def call(transport_response)
        raise NotImplementedError, "parser must implement #call"
      end

      protected

      # Extract JSON from transport response
      def json(transport_response)
        transport_response.json
      end

      # Check if response is successful
      def success?(transport_response)
        transport_response.success?
      end
    end
  end
end

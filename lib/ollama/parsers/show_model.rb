# frozen_string_literal: true

require_relative "base"

module Ollama
  module Parsers
    # Parses show_model responses
    class ShowModel < Base
      def call(transport_response)
        json(transport_response)
      end
    end
  end
end

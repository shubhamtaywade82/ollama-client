# frozen_string_literal: true

require_relative "base"
require_relative "../../response"

module Ollama
  module Parsers
    # Parses chat completion responses
    class Chat < Base
      def call(transport_response)
        data = json(transport_response)
        Response.new(data)
      end
    end
  end
end

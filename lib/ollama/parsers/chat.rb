# frozen_string_literal: true

require_relative "base"
require_relative "../responses/chat"

module Ollama
  module Parsers
    # Parses chat completion responses
    class Chat < Base
      def initialize(provider: nil)
        super()
        @provider = provider
      end

      def call(transport_response)
        data = json(transport_response)
        data = @provider.normalize_chat_response(data) if @provider.respond_to?(:normalize_chat_response)
        Responses::Chat.new(data)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "chat"

module Ollama
  module Serializers
    # Serializes vision/chat requests with image inputs
    class Vision < Chat
    end
  end
end

# frozen_string_literal: true

require_relative "base"

module Ollama
  module Responses
    # Typed response wrapper for generate endpoints
    class Generate < Base
      def context
        @data["context"] || @data[:context]
      end

      def to_s
        content || ""
      end

      def to_str
        to_s
      end
    end
  end
end

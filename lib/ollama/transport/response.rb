# frozen_string_literal: true

module Ollama
  module Transport
    # Normalized transport response contract.
    class Response
      attr_reader :status, :headers, :body, :raw, :duration_ms

      def initialize(status:, headers:, body:, raw:, duration_ms: nil)
        @status = status.to_i
        @headers = headers || {}
        @body = body
        @raw = raw
        @duration_ms = duration_ms
      end

      def json
        @json ||= JSON.parse(body.to_s)
      end

      def success?
        status >= 200 && status < 300
      end

      # Compatibility with existing Net::HTTP response checks
      def is_a?(klass)
        return success? if klass == Net::HTTPSuccess

        super
      end

      def code
        status.to_s
      end

      def message
        raw.respond_to?(:message) ? raw.message : ""
      end
    end
  end
end

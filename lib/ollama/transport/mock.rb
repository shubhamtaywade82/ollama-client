# frozen_string_literal: true

module Ollama
  module Transport
    class Mock < Base
      def initialize(config)
        super
        @queue = []
      end

      def enqueue(status: 200, headers: {}, body: "{}", duration_ms: 0.0)
        @queue << Response.new(status: status, headers: headers, body: body, raw: nil, duration_ms: duration_ms)
      end

      def request(uri:, request:, read_timeout:)
        _ = [uri, request, read_timeout]
        raise Error, "No mocked response enqueued" if @queue.empty?

        @queue.shift
      end

      def stream(_uri:, _request:, &_block)
        raise NotImplementedError, "Mock stream transport not implemented yet"
      end

      def capabilities
        [:request, :mock]
      end
    end
  end
end

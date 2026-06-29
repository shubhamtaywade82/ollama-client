# frozen_string_literal: true

module Ollama
  module Transport
    # In-memory transport for deterministic tests.
    class Mock < Base
      class << self
        def global_queue
          @global_queue ||= []
        end

        def clear!
          global_queue.clear
        end

        def enqueue(status: 200, headers: {}, body: "{}", duration_ms: 0.0)
          global_queue << Response.new(status: status, headers: headers, body: body, raw: nil, duration_ms: duration_ms)
        end
      end

      def initialize(config)
        super
        @queue = []
      end

      def enqueue(status: 200, headers: {}, body: "{}", duration_ms: 0.0)
        @queue << Response.new(status: status, headers: headers, body: body, raw: nil, duration_ms: duration_ms)
      end

      def request(uri:, request:, read_timeout:)
        _ = [uri, request, read_timeout]

        response = @queue.shift || self.class.global_queue.shift
        raise Error, "No mocked response enqueued" unless response

        response
      end

      def stream(_uri:, _request:, &_block)
        raise NotImplementedError, "Mock stream transport not implemented yet"
      end

      def capabilities
        %i[request mock]
      end
    end
  end
end

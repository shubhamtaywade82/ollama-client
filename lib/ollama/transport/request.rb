# frozen_string_literal: true

module Ollama
  module Transport
    # Transport-level request value object.
    # Decouples serialization from the underlying network transport library.
    class Request
      attr_reader :method, :uri, :headers, :body, :stream, :timeout

      def initialize(method:, uri:, headers: {}, body: nil, stream: false, timeout: 120)
        @method = method.to_sym
        @uri = uri
        @headers = headers
        @body = body
        @stream = stream
        @timeout = timeout
      end
    end
  end
end

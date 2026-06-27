# frozen_string_literal: true

module Ollama
  # Pipeline orchestrates the full request lifecycle:
  # Request → Serializer → Transport → Transport::Response → Parser → Domain Response
  class Pipeline
    attr_reader :transport, :serializer, :parser

    def initialize(transport:, serializer:, parser:)
      @transport = transport
      @serializer = serializer
      @parser = parser
    end

    # Execute a non-streaming request through the pipeline
    def call(request)
      serialized = @serializer.call(request)
      transport_response = @transport.request(uri: serialized.uri, request: serialized, read_timeout: serialized.timeout)
      @parser.call(transport_response)
    end

    # Execute a streaming request through the pipeline
    def stream(request, &block)
      serialized = @serializer.call(request)
      @transport.stream(uri: serialized.uri, request: serialized, &block)
    end

    # Convenience: build and execute from endpoint-specific parameters
    def execute(endpoint:, **params)
      request = Request.build(endpoint, **params)
      call(request)
    end
  end
end

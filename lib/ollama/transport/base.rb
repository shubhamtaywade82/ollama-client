# frozen_string_literal: true

require_relative "../errors"
require_relative "response"

module Ollama
  module Transport
    # Base transport adapter contract.
    class Base
      def initialize(config)
        @config = config
      end

      def request(_uri:, _request:, _read_timeout:)
        raise NotImplementedError, "transport adapter must implement #request"
      end

      # Chain entry point used by the pipeline. Surfaces HTTP failures as
      # typed errors (Errors.from_response) *inside* the middleware chain
      # so policies like Retry/AutoPull/Fallback can observe them.
      def call(request, _env = {})
        response = request(
          uri: request.uri,
          request: request,
          read_timeout: request.timeout
        )

        raise Errors.from_response(response) if response.is_a?(Response) && !response.success?

        response
      end

      def stream(_uri:, _request:, &_block)
        raise NotImplementedError, "transport adapter must implement #stream"
      end

      def capabilities
        []
      end
    end
  end
end

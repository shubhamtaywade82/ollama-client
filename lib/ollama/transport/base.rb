# frozen_string_literal: true

module Ollama
  module Transport
    class Base
      def initialize(config)
        @config = config
      end

      def request(_uri:, _request:, _read_timeout:)
        raise NotImplementedError, "transport adapter must implement #request"
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

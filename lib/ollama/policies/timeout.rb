# frozen_string_literal: true

require "net/http"
require_relative "base"

module Ollama
  module Policies
    # Timeout policy - enforces request and connection timeouts
    class Timeout < Base
      attr_reader :connect_timeout, :read_timeout, :write_timeout, :hooks

      # @param connect_timeout [Float] Connection timeout in seconds (default: 5.0)
      # @param read_timeout [Float] Read timeout in seconds (default: 60.0)
      # @param write_timeout [Float] Write timeout in seconds (default: 10.0)
      # @param hooks [Hash] Optional hooks: :on_timeout
      def initialize(
        connect_timeout: 5.0,
        read_timeout: 60.0,
        write_timeout: 10.0,
        hooks: {}
      )
        super()
        @connect_timeout = connect_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
        @hooks = hooks
      end

      def around(request, env, &block)
        # Inject timeouts into request metadata
        env[:timeouts] ||= {}
        env[:timeouts][:connect] = @connect_timeout
        env[:timeouts][:read] = @read_timeout
        env[:timeouts][:write] = @write_timeout

        block.call(request, env)
      rescue TimeoutError, Net::ReadTimeout, Net::OpenTimeout => e
        @hooks[:on_timeout]&.call(request, env, e)
        raise
      end
    end
  end
end

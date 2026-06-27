# frozen_string_literal: true

require_relative "base"
require_relative "retry/strategies/exponential"
require_relative "retry/strategies/linear"
require_relative "retry/strategies/fixed"
require_relative "retry/strategies/jitter"

module Ollama
  module Policies
    # Retry policy - handles automatic retries with configurable backoff strategies
    class Retry < Base
      attr_reader :max_attempts, :strategy, :retryable_errors, :hooks

      # @param max_attempts [Integer] Maximum number of retry attempts (default: 3)
      # @param strategy [Symbol, Class] Backoff strategy: :exponential, :linear, :fixed, :jitter (default: :exponential)
      # @param base_delay [Float] Base delay in seconds for backoff (default: 1.0)
      # @param max_delay [Float] Maximum delay in seconds (default: 60.0)
      # @param jitter [Float] Jitter factor 0.0-1.0 (default: 0.1)
      # @param retryable_errors [Array<Class>] Exception classes to retry (default: standard retryable)
      # @param hooks [Hash] Optional hooks: :before_retry, :after_retry
      def initialize(
        max_attempts: 3,
        strategy: :exponential,
        base_delay: 1.0,
        max_delay: 60.0,
        jitter: 0.1,
        retryable_errors: nil,
        hooks: {}
      )
        super()
        @max_attempts = max_attempts
        @base_delay = base_delay
        @max_delay = max_delay
        @jitter = jitter
        @strategy = build_strategy(strategy)
        @retryable_errors = retryable_errors || default_retryable_errors
        @hooks = hooks
      end

      def call(request, env = {})
        attempt = 0
        last_error = nil

        loop do
          attempt += 1
          env[:attempt] = attempt

          begin
            response = @app.call(request, env)
            return response
          rescue StandardError => e
            last_error = e

            # Check if we should retry
            raise unless retryable?(e, env)
            raise if attempt >= @max_attempts

            # Execute before_retry hook
            @hooks[:before_retry]&.call(request, env, e, attempt)

            # Calculate delay
            delay = @strategy.delay(attempt, @base_delay, @max_delay, @jitter)

            # Sleep
            sleep(delay) if delay.positive?

            # Execute after_retry hook
            @hooks[:after_retry]&.call(request, env, e, attempt, delay)
          end
        end
      rescue StandardError => e
        # If we exhausted retries, raise the last error
        raise last_error || e
      end

      def stream(request, env = {}, &block)
        @app.stream(request, env, &block)
      end

      private

      def build_strategy(strategy)
        case strategy
        when :exponential
          Strategies::Exponential.new
        when :linear
          Strategies::Linear.new
        when :fixed
          Strategies::Fixed.new
        when :jitter
          Strategies::Jitter.new
        when Class
          strategy.new
        else
          raise ArgumentError, "Unknown retry strategy: #{strategy}"
        end
      end

      def default_retryable_errors
        [
          TimeoutError,
          Errno::ECONNREFUSED,
          Errno::EHOSTUNREACH,
          Errno::ETIMEDOUT,
          SocketError,
          IOError,
          HTTPError
        ].freeze
      end

      def retryable?(error, _env)
        # Check if error class is in retryable list
        return true if @retryable_errors.any? { |cls| error.is_a?(cls) }

        # Check for HTTP 429 (rate limit) and 5xx
        if error.respond_to?(:status)
          status = error.status
          return true if status == 429 || (status >= 500 && status < 600)
        end

        # Check for HTTP 429 in response
        if error.respond_to?(:response) && error.response&.code
          code = error.response.code.to_i
          return true if code == 429 || (code >= 500 && code < 600)
        end

        false
      end
    end
  end
end

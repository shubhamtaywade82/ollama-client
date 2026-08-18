# frozen_string_literal: true

require "net/http"
require_relative "base"

module Ollama
  # Policy objects modeling production behaviors (retry, timeout, etc.) — see
  # lib/ollama/policies/base.rb for current status.
  module Policies
    # Retry policy - handles automatic retries with configurable backoff strategies
    #
    # Declared here as an empty stub (before requiring the strategy files
    # below) so that Retry's superclass is established as Base first — the
    # strategy files reopen this same class to nest their Strategies module
    # under it, and Ruby raises "superclass mismatch" if a class is reopened
    # with a different (or absent) superclass than its first declaration.
    class Retry < Base
    end

    require_relative "retry/strategies/exponential"
    require_relative "retry/strategies/linear"
    require_relative "retry/strategies/fixed"
    require_relative "retry/strategies/jitter"

    # (continued from the stub declaration above, now that Strategies exists)
    class Retry
      attr_reader :max_attempts, :strategy, :retryable_errors, :hooks

      # @param max_attempts [Integer] Maximum number of retry attempts (default: 3)
      # @param strategy [Symbol, Class] Backoff strategy: :exponential, :linear, :fixed, :jitter (default: :exponential)
      # @param base_delay [Float] Base delay in seconds for backoff (default: 1.0)
      # @param max_delay [Float] Maximum delay in seconds (default: 60.0)
      # @param jitter [Float] Jitter factor 0.0-1.0 (default: 0.1)
      # @param retryable_errors [Array<Class>] Exception classes to retry (default: standard retryable)
      # @param hooks [Hash] Optional hooks: :before_retry, :after_retry
      # rubocop:disable Metrics/ParameterLists
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
      # rubocop:enable Metrics/ParameterLists

      def around(request, env, &block)
        attempt = 0
        last_error = nil

        loop do
          attempt += 1
          env[:attempt] = attempt

          begin
            return block.call(request, env)
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
          Net::ReadTimeout,
          Net::OpenTimeout,
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

        server_error?(status_of(error)) || server_error?(response_code_of(error))
      end

      def status_of(error)
        if error.respond_to?(:status_code)
          error.status_code
        elsif error.respond_to?(:status)
          error.status
        end
      end

      def response_code_of(error)
        return unless error.respond_to?(:response) && error.response&.code

        error.response.code.to_i
      end

      # Retry on 429 (rate limit) and 5xx server errors.
      def server_error?(status)
        status == 429 || (status.is_a?(Integer) && status >= 500 && status < 600)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base"

module Ollama
  module Policies
    # RateLimit policy - token bucket rate limiter
    class RateLimit < Base
      attr_reader :requests_per_second, :requests_per_minute, :burst, :bucket, :hooks

      # @param requests_per_second [Float] Maximum requests per second (default: 10.0)
      # @param requests_per_minute [Integer] Maximum requests per minute (default: 300)
      # @param burst [Integer] Maximum burst size (default: 20)
      # @param hooks [Hash] Optional hooks: :rate_limited, :bucket_refilled
      def initialize(
        requests_per_second: 10.0,
        requests_per_minute: 300,
        burst: 20,
        hooks: {}
      )
        super()
        @requests_per_second = requests_per_second
        @requests_per_minute = requests_per_minute
        @burst = burst
        @hooks = hooks

        # Initialize token buckets
        @second_bucket = TokenBucket.new(
          rate: requests_per_second,
          capacity: [burst, requests_per_second].max
        )
        @minute_bucket = TokenBucket.new(
          rate: requests_per_minute / 60.0,
          capacity: [burst * 10, requests_per_minute].max
        )
      end

      def call(request, env = {})
        # Wait for both buckets to have tokens
        wait_for_tokens(@second_bucket)
        wait_for_tokens(@minute_bucket)

        # Consume tokens
        @second_bucket.consume(1)
        @minute_bucket.consume(1)

        @app.call(request, env)
      end

      def stream(request, env = {}, &block)
        call(request, env) { |req, env| @app.stream(req, env, &block) }
      end

      private

      def wait_for_tokens(bucket)
        loop do
          return if bucket.available? >= 1

          sleep_time = bucket.time_until_ready(1)
          @hooks[:rate_limited]&.call(bucket, sleep_time)
          sleep(sleep_time)
        end
      end

      # Token bucket implementation
      class TokenBucket
        attr_reader :rate, :capacity, :tokens, :last_refill

        def initialize(rate:, capacity:)
          @rate = rate.to_f
          @capacity = capacity.to_f
          @tokens = capacity.to_f
          @last_refill = Time.now.to_f
          @mutex = Mutex.new
        end

        def consume(amount = 1)
          @mutex.synchronize do
            refill
            if @tokens >= amount
              @tokens -= amount
              true
            else
              false
            end
          end
        end

        def available?
          @mutex.synchronize do
            refill
            @tokens
          end
        end

        def time_until_ready(amount = 1)
          @mutex.synchronize do
            refill
            return 0 if @tokens >= amount

            needed = amount - @tokens
            needed / @rate
          end
        end

        private

        def refill
          now = Time.now.to_f
          elapsed = now - @last_refill
          new_tokens = elapsed * @rate
          @tokens = [@capacity, @tokens + new_tokens].min
          @last_refill = now
        end
      end
    end
  end
end

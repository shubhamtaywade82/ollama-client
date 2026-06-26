# frozen_string_literal: true

module Ollama
  # Shared request wrapper for API-key rotation on HTTP 429 responses.
  #
  # Classes including this module must expose `@config` and may override `sleep`
  # in tests. The wrapper keeps retry state local to the method invocation and
  # never mutates request-global counters.
  module RateLimitHandler
    private

    def with_rate_limit_key_rotation
      pool = @config.api_key_pool
      return yield(nil) if pool.empty?

      backoff_attempt = 0
      last_error = nil

      loop do
        context = pool.request_context

        pool.size.times do |offset|
          key = pool.key_for(context, offset: offset)

          begin
            return yield(key)
          rescue HTTPError => e
            raise unless e.status_code == 429

            last_error = e
          end
        end

        if backoff_attempt >= @config.retries
          raise RateLimitExhaustedError.new(rate_limit_exhausted_message(pool.size, backoff_attempt, last_error), 429)
        end

        backoff_attempt += 1
        sleep(2**backoff_attempt)
      end
    end

    def rate_limit_exhausted_message(key_count, backoff_attempt, last_error)
      detail = last_error&.message || "HTTP 429: Too Many Requests"
      "#{detail}; exhausted #{key_count} API key(s) after #{backoff_attempt} backoff retry cycle(s)"
    end
  end
end

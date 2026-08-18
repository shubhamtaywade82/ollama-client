# frozen_string_literal: true

module Ollama
  module Policies
    class Retry
      module Strategies
        # Exponential backoff: base_delay * 2^(attempt-1)
        class Exponential
          def delay(attempt, base_delay, max_delay, jitter)
            delay = base_delay * (2**(attempt - 1))
            delay = [delay, max_delay].min
            apply_jitter(delay, jitter)
          end

          private

          def apply_jitter(delay, jitter)
            return delay if jitter.zero?

            factor = 1.0 + ((rand * jitter * 2) - jitter) # ±jitter
            (delay * factor).round(3)
          end
        end
      end
    end
  end
end

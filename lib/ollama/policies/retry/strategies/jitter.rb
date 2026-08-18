# frozen_string_literal: true

module Ollama
  module Policies
    class Retry
      module Strategies
        # Jitter backoff: random delay between 0 and base_delay * 2^(attempt-1)
        class Jitter
          def delay(attempt, base_delay, max_delay, jitter)
            # Full jitter: random value between 0 and exponential backoff
            max_exponential = base_delay * (2**(attempt - 1))
            max_exponential = [max_exponential, max_delay].min

            delay = rand * max_exponential
            apply_jitter(delay, jitter)
          end

          private

          def apply_jitter(delay, jitter)
            return delay if jitter.zero?

            factor = 1.0 + (rand * ((jitter * 2) - jitter))
            (delay * factor).round(3)
          end
        end
      end
    end
  end
end

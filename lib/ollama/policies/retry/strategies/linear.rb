# frozen_string_literal: true

module Ollama
  module Policies
    module Retry
      module Strategies
        # Linear backoff: base_delay * attempt
        class Linear
          def delay(attempt, base_delay, max_delay, jitter)
            delay = base_delay * attempt
            delay = [delay, max_delay].min
            apply_jitter(delay, jitter)
          end

          private

          def apply_jitter(delay, jitter)
            return delay if jitter.zero?

            factor = 1.0 + ((rand * jitter * 2) - jitter)
            (delay * factor).round(3)
          end
        end
      end
    end
  end
end

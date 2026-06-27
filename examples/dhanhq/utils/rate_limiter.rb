# frozen_string_literal: true

module DhanHQ
  module Utils
    # Rate limiter for DhanHQ MarketFeed APIs (1 request per second)
    class RateLimiter
      MARKETFEED_INTERVAL = 1.1 # 1 second + 0.1s buffer

      @last_marketfeed_call = nil
      @marketfeed_mutex = Mutex.new

      def self.marketfeed
        @marketfeed_mutex.synchronize do
          if @last_marketfeed_call
            elapsed = Time.now - @last_marketfeed_call
            sleep(MARKETFEED_INTERVAL - elapsed) if elapsed < MARKETFEED_INTERVAL
          end
          @last_marketfeed_call = Time.now
        end
      end
    end
  end
end

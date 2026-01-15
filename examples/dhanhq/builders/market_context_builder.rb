# frozen_string_literal: true

module DhanHQ
  module Builders
    # Builds human-readable market context from raw market data
    class MarketContextBuilder
      def self.build(market_data)
        new(market_data).build
      end

      def initialize(market_data)
        @market_data = market_data || {}
      end

      def build
        context_parts = []
        context_parts << build_nifty_context
        context_parts << build_reliance_context
        context_parts << build_positions_context
        context_parts.compact.join("\n")
      end

      private

      def build_nifty_context
        return "NIFTY data not available" unless @market_data[:nifty]

        ltp = @market_data[:nifty][:ltp]
        change = @market_data[:nifty][:change_percent]

        if ltp && ltp != 0
          "NIFTY is trading at #{ltp} (#{change || 'unknown'}% change)"
        else
          "NIFTY data retrieved but LTP is not available (may be outside market hours)"
        end
      end

      def build_reliance_context
        return "RELIANCE data not available" unless @market_data[:reliance]

        ltp = @market_data[:reliance][:ltp]
        change = @market_data[:reliance][:change_percent]
        volume = @market_data[:reliance][:volume]

        if ltp && ltp != 0
          "RELIANCE is at #{ltp} (#{change || 'unknown'}% change, Volume: #{volume || 'N/A'})"
        else
          "RELIANCE data retrieved but LTP is not available (may be outside market hours)"
        end
      end

      def build_positions_context
        positions = @market_data[:positions] || []

        if positions.empty?
          "Current positions: None"
        else
          parts = ["Current positions: #{positions.length} active"]
          positions.each do |pos|
            parts << "  - #{pos[:trading_symbol]}: #{pos[:quantity]} @ #{pos[:average_price]}"
          end
          parts.join("\n")
        end
      end
    end
  end
end

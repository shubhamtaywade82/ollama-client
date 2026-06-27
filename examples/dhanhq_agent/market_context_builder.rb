# frozen_string_literal: true

module DhanHQAgent
  # Builds a human-readable market context from raw DhanHQ data.
  class MarketContextBuilder
    def self.build(market_data)
      new(market_data).build
    end

    def initialize(market_data)
      @market_data = market_data
    end

    def build
      context_parts = []

      context_parts << index_summary(:nifty, "NIFTY")
      context_parts << equity_summary(:reliance, "RELIANCE")
      context_parts.concat(positions_summary)

      context_parts.join("\n")
    end

    private

    attr_reader :market_data

    def index_summary(key, label)
      instrument_summary(key, label)
    end

    def equity_summary(key, label)
      instrument_summary(key, label, include_volume: true)
    end

    def instrument_summary(key, label, include_volume: false)
      instrument_data = market_data[key]
      return "#{label} data not available" unless instrument_data

      ltp = instrument_data[:ltp]
      return "#{label} data retrieved but LTP is not available (may be outside market hours)" unless present_price?(ltp)

      change = instrument_data[:change_percent]
      summary = "#{label} is trading at #{ltp} (#{change || 'unknown'}% change)"

      return summary unless include_volume

      volume = instrument_data[:volume]
      "#{label} is at #{ltp} (#{change || 'unknown'}% change, Volume: #{volume || 'N/A'})"
    end

    def positions_summary
      positions = market_data.fetch(:positions, [])
      return ["Current positions: None"] if positions.empty?

      summary = ["Current positions: #{positions.length} active"]
      positions.each do |position|
        summary << "  - #{position[:trading_symbol]}: #{position[:quantity]} @ #{position[:average_price]}"
      end
      summary
    end

    def present_price?(ltp)
      ltp && ltp != 0
    end
  end
end


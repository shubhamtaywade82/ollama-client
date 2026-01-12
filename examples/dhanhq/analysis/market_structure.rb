# frozen_string_literal: true

require_relative "../indicators/technical_indicators"

module DhanHQ
  module Analysis
    # Market Structure Analysis (SMC - Smart Money Concepts)
    class MarketStructure
      def self.analyze_trend(highs, lows, closes)
        return { trend: :unknown, strength: 0 } if closes.nil? || closes.length < 3

        # Higher highs and higher lows = Uptrend
        # Lower highs and lower lows = Downtrend
        recent_highs = highs.last(10) if highs
        recent_lows = lows.last(10) if lows
        recent_closes = closes.last(10)

        higher_highs = recent_highs ? recent_highs.each_cons(2).all? { |a, b| b >= a } : false
        higher_lows = recent_lows ? recent_lows.each_cons(2).all? { |a, b| b >= a } : false
        lower_highs = recent_highs ? recent_highs.each_cons(2).all? { |a, b| b <= a } : false
        lower_lows = recent_lows ? recent_lows.each_cons(2).all? { |a, b| b <= a } : false

        trend = if higher_highs && higher_lows
                  :uptrend
                elsif lower_highs && lower_lows
                  :downtrend
                else
                  :sideways
                end

        # Calculate trend strength using moving averages
        sma_20 = DhanHQ::Indicators::TechnicalIndicators.sma(closes, 20)
        sma_50 = DhanHQ::Indicators::TechnicalIndicators.sma(closes, 50)

        strength = if sma_20.last && sma_50.last
                     ((sma_20.last - sma_50.last) / sma_50.last * 100).abs
                   else
                     0
                   end

        { trend: trend, strength: strength.round(2) }
      end

      # Smart Money Concepts: Order Blocks
      def self.find_order_blocks(highs, lows, closes, volumes)
        return [] if closes.nil? || closes.length < 5

        order_blocks = []

        (4...closes.length).each do |i|
          # Bullish order block: strong move up after consolidation
          if closes[i] > closes[i - 1] && closes[i - 1] > closes[i - 2] &&
             volumes[i] > volumes[i - 1] * 1.5
            order_blocks << {
              type: :bullish,
              price_range: [lows[i - 2], highs[i]],
              timestamp: i,
              volume: volumes[i]
            }
          end

          # Bearish order block: strong move down after consolidation
          next unless closes[i] < closes[i - 1] && closes[i - 1] < closes[i - 2] &&
                      volumes[i] > volumes[i - 1] * 1.5

          order_blocks << {
            type: :bearish,
            price_range: [lows[i], highs[i - 2]],
            timestamp: i,
            volume: volumes[i]
          }
        end

        order_blocks
      end

      # Liquidity Zones (SMC)
      def self.find_liquidity_zones(highs, lows, closes, lookback = 50)
        return { buy_side: [], sell_side: [] } if closes.nil? || closes.length < lookback

        # Buy-side liquidity: areas where stops are likely (below support)
        # Sell-side liquidity: areas where stops are likely (above resistance)

        support_resistance = DhanHQ::Indicators::TechnicalIndicators.support_resistance(
          highs, lows, closes, lookback
        )

        current_price = closes.last
        buy_side = support_resistance[:support].select { |s| s[:price] < current_price }
        sell_side = support_resistance[:resistance].select { |r| r[:price] > current_price }

        { buy_side: buy_side, sell_side: sell_side }
      end

      # Market Structure Break (Change in trend)
      def self.detect_structure_break(highs, lows, closes)
        return { broken: false, direction: nil } if closes.nil? || closes.length < 10

        trend = analyze_trend(highs, lows, closes)

        # Structure break: previous high/low is broken
        recent_high = highs ? highs.last(5).max : closes.last(5).max
        recent_low = lows ? lows.last(5).min : closes.last(5).min
        previous_high = highs ? highs[-10..-6].max : closes[-10..-6].max
        previous_low = lows ? lows[-10..-6].min : closes[-10..-6].min

        broken = false
        direction = nil

        if recent_high > previous_high && trend[:trend] != :uptrend
          broken = true
          direction = :bullish_break
        elsif recent_low < previous_low && trend[:trend] != :downtrend
          broken = true
          direction = :bearish_break
        end

        { broken: broken, direction: direction, current_trend: trend[:trend] }
      end
    end
  end
end

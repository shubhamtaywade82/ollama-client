# frozen_string_literal: true

require_relative "market_structure"
require_relative "pattern_recognizer"
require_relative "../indicators/technical_indicators"

module DhanHQ
  module Analysis
    # Comprehensive trend analysis
    class TrendAnalyzer
      def self.analyze(ohlc_data)
        return {} if ohlc_data.nil? || ohlc_data.empty?

        closes = extract_closes(ohlc_data)
        highs = extract_highs(ohlc_data)
        lows = extract_lows(ohlc_data)
        opens = extract_opens(ohlc_data)
        volumes = extract_volumes(ohlc_data)

        return {} if closes.nil? || closes.empty?

        # Technical indicators
        sma_20 = DhanHQ::Indicators::TechnicalIndicators.sma(closes, 20)
        sma_50 = DhanHQ::Indicators::TechnicalIndicators.sma(closes, 50)
        ema_12 = DhanHQ::Indicators::TechnicalIndicators.ema(closes, 12)
        rsi = DhanHQ::Indicators::TechnicalIndicators.rsi(closes, 14)
        macd = DhanHQ::Indicators::TechnicalIndicators.macd(closes)

        # Market structure
        trend = MarketStructure.analyze_trend(highs, lows, closes)
        structure_break = MarketStructure.detect_structure_break(highs, lows, closes)
        support_resistance = DhanHQ::Indicators::TechnicalIndicators.support_resistance(highs, lows, closes)

        # Patterns
        candlestick_patterns = PatternRecognizer.detect_candlestick_patterns(opens, highs, lows, closes)
        chart_patterns = PatternRecognizer.detect_chart_patterns(highs, lows, closes)

        # SMC Analysis
        order_blocks = MarketStructure.find_order_blocks(highs, lows, closes, volumes || [])
        liquidity_zones = MarketStructure.find_liquidity_zones(highs, lows, closes)

        {
          trend: trend,
          structure_break: structure_break,
          indicators: {
            sma_20: sma_20.last,
            sma_50: sma_50.last,
            ema_12: ema_12.last,
            rsi: rsi.last,
            macd: macd[:macd].last,
            macd_signal: macd[:signal].last,
            macd_histogram: macd[:histogram].last
          },
          support_resistance: support_resistance,
          patterns: {
            candlestick: candlestick_patterns.last(5),
            chart: chart_patterns
          },
          smc: {
            order_blocks: order_blocks.last(3),
            liquidity_zones: liquidity_zones
          },
          current_price: closes.last
        }
      end

      private

      def self.extract_closes(data)
        data.map { |d| d[:close] || d["close"] || d["c"] || d[:c] }.compact
      end

      def self.extract_highs(data)
        data.map { |d| d[:high] || d["high"] || d["h"] || d[:h] }.compact
      end

      def self.extract_lows(data)
        data.map { |d| d[:low] || d["low"] || d["l"] || d[:l] }.compact
      end

      def self.extract_opens(data)
        data.map { |d| d[:open] || d["open"] || d["o"] || d[:o] }.compact
      end

      def self.extract_volumes(data)
        data.map { |d| d[:volume] || d["volume"] || d["v"] || d[:v] }.compact
      end
    end
  end
end

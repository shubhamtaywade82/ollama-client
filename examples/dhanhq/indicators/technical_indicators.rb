# frozen_string_literal: true

module DhanHQ
  module Indicators
    # Technical analysis indicators
    class TechnicalIndicators
      # Simple Moving Average
      def self.sma(prices, period)
        return [] if prices.nil? || prices.empty? || period < 1

        prices.each_cons(period).map { |window| window.sum.to_f / period }
      end

      # Exponential Moving Average
      def self.ema(prices, period)
        return [] if prices.nil? || prices.empty? || period < 1

        multiplier = 2.0 / (period + 1)
        ema_values = []
        ema_values << prices.first.to_f

        prices[1..].each do |price|
          ema_values << ((price.to_f - ema_values.last) * multiplier + ema_values.last)
        end

        ema_values
      end

      # Relative Strength Index
      def self.rsi(prices, period = 14)
        return [] if prices.nil? || prices.length < period + 1

        gains = []
        losses = []

        prices.each_cons(2) do |prev, curr|
          change = curr - prev
          gains << [change, 0].max
          losses << (change.negative? ? -change : 0)
        end

        rsi_values = []
        avg_gain = gains.first(period).sum.to_f / period
        avg_loss = losses.first(period).sum.to_f / period

        rsi_values << calculate_rsi_value(avg_gain, avg_loss)

        (period...gains.length).each do |i|
          avg_gain = ((avg_gain * (period - 1)) + gains[i]) / period
          avg_loss = ((avg_loss * (period - 1)) + losses[i]) / period
          rsi_values << calculate_rsi_value(avg_gain, avg_loss)
        end

        rsi_values
      end

      # MACD (Moving Average Convergence Divergence)
      def self.macd(prices, fast_period = 12, slow_period = 26, signal_period = 9)
        return { macd: [], signal: [], histogram: [] } if prices.nil? || prices.empty?

        fast_ema = ema(prices, fast_period)
        slow_ema = ema(prices, slow_period)

        min_length = [fast_ema.length, slow_ema.length].min
        macd_line = fast_ema.last(min_length).zip(slow_ema.last(min_length)).map { |f, s| f - s }

        signal_line = ema(macd_line, signal_period)
        histogram = macd_line.last(signal_line.length).zip(signal_line).map { |m, s| m - s }

        {
          macd: macd_line,
          signal: signal_line,
          histogram: histogram
        }
      end

      # Bollinger Bands
      def self.bollinger_bands(prices, period = 20, std_dev = 2)
        return { upper: [], middle: [], lower: [] } if prices.nil? || prices.empty?

        sma_values = sma(prices, period)
        bands = { upper: [], middle: sma_values, lower: [] }

        prices.each_cons(period).with_index do |window, idx|
          mean = sma_values[idx]
          variance = window.map { |p| (p - mean)**2 }.sum / period
          std = Math.sqrt(variance)

          bands[:upper] << mean + (std_dev * std)
          bands[:lower] << mean - (std_dev * std)
        end

        bands
      end

      # Average True Range
      def self.atr(highs, lows, closes, period = 14)
        return [] if highs.nil? || lows.nil? || closes.nil?
        return [] if [highs.length, lows.length, closes.length].min < 2

        true_ranges = []
        (1...highs.length).each do |i|
          tr1 = highs[i] - lows[i]
          tr2 = (highs[i] - closes[i - 1]).abs
          tr3 = (lows[i] - closes[i - 1]).abs
          true_ranges << [tr1, tr2, tr3].max
        end

        return [] if true_ranges.length < period

        atr_values = []
        atr_values << true_ranges.first(period).sum.to_f / period

        (period...true_ranges.length).each do |i|
          atr = ((atr_values.last * (period - 1)) + true_ranges[i]) / period
          atr_values << atr
        end

        atr_values
      end

      # Support and Resistance levels
      def self.support_resistance(highs, lows, closes, lookback = 20)
        return { support: [], resistance: [] } if highs.nil? || lows.nil? || closes.nil?

        support_levels = []
        resistance_levels = []

        (lookback...highs.length).each do |i|
          window_highs = highs[(i - lookback)..i]
          window_lows = lows[(i - lookback)..i]

          local_high = window_highs.max
          local_low = window_lows.min

          # Resistance: price touched high multiple times
          if window_highs.count(local_high) >= 2
            resistance_levels << { price: local_high, strength: window_highs.count(local_high) }
          end

          # Support: price touched low multiple times
          if window_lows.count(local_low) >= 2
            support_levels << { price: local_low, strength: window_lows.count(local_low) }
          end
        end

        { support: support_levels.uniq { |s| s[:price] }, resistance: resistance_levels.uniq { |r| r[:price] } }
      end

      def self.calculate_rsi_value(avg_gain, avg_loss)
        return 100 if avg_loss.zero?

        rs = avg_gain / avg_loss
        100 - (100 / (1 + rs))
      end
    end
  end
end

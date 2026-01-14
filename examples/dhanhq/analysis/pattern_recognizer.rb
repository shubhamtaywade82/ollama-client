# frozen_string_literal: true

module DhanHQ
  module Analysis
    # Candlestick and chart pattern recognition
    class PatternRecognizer
      # Detect common candlestick patterns
      def self.detect_candlestick_patterns(opens, highs, lows, closes)
        return [] if closes.nil? || closes.length < 3

        patterns = []

        (2...closes.length).each do |i|
          first_candle = build_candle(opens, highs, lows, closes, i - 2)
          second_candle = build_candle(opens, highs, lows, closes, i - 1)
          third_candle = build_candle(opens, highs, lows, closes, i)

          # Engulfing patterns
          if bullish_engulfing?(first_candle, second_candle)
            patterns << { type: :bullish_engulfing, index: i, strength: :medium }
          end

          if bearish_engulfing?(first_candle, second_candle)
            patterns << { type: :bearish_engulfing, index: i, strength: :medium }
          end

          # Hammer pattern
          patterns << { type: :hammer, index: i - 1, strength: :medium } if hammer?(second_candle)

          # Shooting star
          patterns << { type: :shooting_star, index: i - 1, strength: :medium } if shooting_star?(second_candle)

          # Three white soldiers / three black crows
          if three_white_soldiers?([first_candle, second_candle, third_candle])
            patterns << { type: :three_white_soldiers, index: i, strength: :strong }
          end

          if three_black_crows?([first_candle, second_candle, third_candle])
            patterns << { type: :three_black_crows, index: i, strength: :strong }
          end
        end

        patterns
      end

      # Detect chart patterns
      def self.detect_chart_patterns(highs, lows, closes)
        return [] if closes.nil? || closes.length < 20

        patterns = []

        # Head and Shoulders (simplified)
        if head_and_shoulders?(highs, lows)
          patterns << { type: :head_and_shoulders, strength: :strong, direction: :bearish }
        end

        # Double Top/Bottom
        double_pattern = double_top_bottom?(highs, lows, closes)
        patterns << double_pattern if double_pattern

        patterns
      end

      def self.bullish_engulfing?(first_candle, second_candle)
        first_open = first_candle[:open]
        first_close = first_candle[:close]
        second_open = second_candle[:open]
        second_close = second_candle[:close]

        first_close < first_open && # First candle is bearish
          second_close > second_open && # Second candle is bullish
          second_open < first_close && # Second opens below first close
          second_close > first_open # Second closes above first open
      end

      def self.bearish_engulfing?(first_candle, second_candle)
        first_open = first_candle[:open]
        first_close = first_candle[:close]
        second_open = second_candle[:open]
        second_close = second_candle[:close]

        first_close > first_open && # First candle is bullish
          second_close < second_open && # Second candle is bearish
          second_open > first_close && # Second opens above first close
          second_close < first_open # Second closes below first open
      end

      def self.hammer?(candle)
        body = (candle[:close] - candle[:open]).abs
        lower_shadow = [candle[:open], candle[:close]].min - candle[:low]
        upper_shadow = candle[:high] - [candle[:open], candle[:close]].max

        lower_shadow > body * 2 && upper_shadow < body * 0.5
      end

      def self.shooting_star?(candle)
        body = (candle[:close] - candle[:open]).abs
        upper_shadow = candle[:high] - [candle[:open], candle[:close]].max
        lower_shadow = [candle[:open], candle[:close]].min - candle[:low]

        upper_shadow > body * 2 && lower_shadow < body * 0.5
      end

      def self.three_white_soldiers?(candles)
        first, second, third = candles
        first[:close] > first[:open] &&
          second[:close] > second[:open] &&
          third[:close] > third[:open] && # All bullish
          second[:close] > first[:close] &&
          third[:close] > second[:close] # Each closes higher
      end

      def self.three_black_crows?(candles)
        first, second, third = candles
        first[:close] < first[:open] &&
          second[:close] < second[:open] &&
          third[:close] < third[:open] && # All bearish
          second[:close] < first[:close] &&
          third[:close] < second[:close] # Each closes lower
      end

      def self.head_and_shoulders?(highs, _lows)
        return false if highs.length < 20

        # Simplified: look for three peaks with middle one highest
        peaks = find_peaks(highs)
        return false if peaks.length < 3

        # Check if middle peak is highest (head)
        middle_idx = peaks.length / 2
        head = peaks[middle_idx]
        left_shoulder = peaks[middle_idx - 1]
        right_shoulder = peaks[middle_idx + 1]

        head[:value] > left_shoulder[:value] && head[:value] > right_shoulder[:value]
      end

      def self.double_top_bottom?(highs, lows, _closes)
        return false if highs.length < 20

        # Double top: two similar highs with dip in between
        peaks = find_peaks(highs)
        troughs = find_troughs(lows)

        if peaks.length >= 2
          peak1 = peaks[-2]
          peak2 = peaks[-1]
          # Check if peaks are similar (within 2%)
          if (peak1[:value] - peak2[:value]).abs / peak1[:value] < 0.02
            return { type: :double_top, strength: :medium, direction: :bearish }
          end
        end

        if troughs.length >= 2
          trough1 = troughs[-2]
          trough2 = troughs[-1]
          # Check if troughs are similar
          if (trough1[:value] - trough2[:value]).abs / trough1[:value] < 0.02
            return { type: :double_bottom, strength: :medium, direction: :bullish }
          end
        end

        false
      end

      def self.find_peaks(values)
        peaks = []
        (1...(values.length - 1)).each do |i|
          peaks << { index: i, value: values[i] } if values[i] > values[i - 1] && values[i] > values[i + 1]
        end
        peaks
      end

      def self.find_troughs(values)
        troughs = []
        (1...(values.length - 1)).each do |i|
          troughs << { index: i, value: values[i] } if values[i] < values[i - 1] && values[i] < values[i + 1]
        end
        troughs
      end

      def self.build_candle(opens, highs, lows, closes, index)
        {
          open: opens[index],
          high: highs[index],
          low: lows[index],
          close: closes[index]
        }
      end
    end
  end
end

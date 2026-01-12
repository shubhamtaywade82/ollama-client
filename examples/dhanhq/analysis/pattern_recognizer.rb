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
          o1, h1, l1, c1 = opens[i - 2], highs[i - 2], lows[i - 2], closes[i - 2]
          o2, h2, l2, c2 = opens[i - 1], highs[i - 1], lows[i - 1], closes[i - 1]
          o3, h3, l3, c3 = opens[i], highs[i], lows[i], closes[i]

          # Engulfing patterns
          if bullish_engulfing?(o1, c1, o2, c2)
            patterns << { type: :bullish_engulfing, index: i, strength: :medium }
          end

          if bearish_engulfing?(o1, c1, o2, c2)
            patterns << { type: :bearish_engulfing, index: i, strength: :medium }
          end

          # Hammer pattern
          if hammer?(o2, h2, l2, c2)
            patterns << { type: :hammer, index: i - 1, strength: :medium }
          end

          # Shooting star
          if shooting_star?(o2, h2, l2, c2)
            patterns << { type: :shooting_star, index: i - 1, strength: :medium }
          end

          # Three white soldiers / three black crows
          if three_white_soldiers?(c1, c2, c3, o1, o2, o3)
            patterns << { type: :three_white_soldiers, index: i, strength: :strong }
          end

          if three_black_crows?(c1, c2, c3, o1, o2, o3)
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

      private

      def self.bullish_engulfing?(o1, c1, o2, c2)
        c1 < o1 && # First candle is bearish
          c2 > o2 && # Second candle is bullish
          o2 < c1 && # Second opens below first close
          c2 > o1 # Second closes above first open
      end

      def self.bearish_engulfing?(o1, c1, o2, c2)
        c1 > o1 && # First candle is bullish
          c2 < o2 && # Second candle is bearish
          o2 > c1 && # Second opens above first close
          c2 < o1 # Second closes below first open
      end

      def self.hammer?(open, high, low, close)
        body = (close - open).abs
        lower_shadow = [open, close].min - low
        upper_shadow = high - [open, close].max

        lower_shadow > body * 2 && upper_shadow < body * 0.5
      end

      def self.shooting_star?(open, high, low, close)
        body = (close - open).abs
        upper_shadow = high - [open, close].max
        lower_shadow = [open, close].min - low

        upper_shadow > body * 2 && lower_shadow < body * 0.5
      end

      def self.three_white_soldiers?(c1, c2, c3, o1, o2, o3)
        c1 > o1 && c2 > o2 && c3 > o3 && # All bullish
          c2 > c1 && c3 > c2 # Each closes higher
      end

      def self.three_black_crows?(c1, c2, c3, o1, o2, o3)
        c1 < o1 && c2 < o2 && c3 < o3 && # All bearish
          c2 < c1 && c3 < c2 # Each closes lower
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

      def self.double_top_bottom?(highs, lows, closes)
        return nil if highs.length < 20

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

        nil
      end

      def self.find_peaks(values)
        peaks = []
        (1...(values.length - 1)).each do |i|
          if values[i] > values[i - 1] && values[i] > values[i + 1]
            peaks << { index: i, value: values[i] }
          end
        end
        peaks
      end

      def self.find_troughs(values)
        troughs = []
        (1...(values.length - 1)).each do |i|
          if values[i] < values[i - 1] && values[i] < values[i + 1]
            troughs << { index: i, value: values[i] }
          end
        end
        troughs
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../analysis/trend_analyzer"
require_relative "../services/data_service"

module DhanHQ
  module Scanners
    # Scanner for swing trading candidates
    class SwingScanner
      def initialize
        @data_service = Services::DataService.new
      end

      def scan_symbols(symbols, exchange_segment: "NSE_EQ", min_score: 40, verbose: false)
        candidates = []
        rejected = []

        symbols.each do |symbol|
          analysis = analyze_symbol(symbol, exchange_segment)

          if analysis[:error]
            rejected << { symbol: symbol, reason: analysis[:error] }
            next
          end

          score = calculate_swing_score(analysis[:analysis])
          score_details = calculate_swing_score_details(analysis[:analysis])

          if score < min_score
            rejected << {
              symbol: symbol,
              score: score,
              reason: "Below minimum score (#{min_score})",
              details: score_details
            }
            next
          end

          candidates << {
            symbol: symbol,
            score: score,
            analysis: analysis[:analysis],
            recommendation: analysis[:interpretation],
            score_details: score_details
          }
        end

        if verbose && !rejected.empty?
          puts "   📋 Rejected candidates:"
          rejected.each do |r|
            puts "      ❌ #{r[:symbol]}: Score #{r[:score]}/100 - #{r[:reason]}"
            if r[:details]
              puts "         Breakdown: Trend=#{r[:details][:trend]}, RSI=#{r[:details][:rsi]}, MACD=#{r[:details][:macd]}, Structure=#{r[:details][:structure]}, Patterns=#{r[:details][:patterns]}"
            end
          end
        end

        candidates.sort_by { |c| -c[:score] }
      end

      def scan_by_criteria(criteria = {})
        # This would typically fetch a list of symbols from an API
        # For now, return empty - would need symbol list source
        []
      end

      private

      def analyze_symbol(symbol, exchange_segment)
        result = @data_service.execute(
          action: "get_historical_data",
          params: {
            "symbol" => symbol,
            "exchange_segment" => exchange_segment,
            "from_date" => (Date.today - 90).strftime("%Y-%m-%d"),
            "to_date" => Date.today.strftime("%Y-%m-%d")
          }
        )

        return { error: "Failed to fetch data: #{result[:error] || 'Unknown error'}" } if result[:error]
        return { error: "No result data returned" } unless result[:result]

        ohlc_data = convert_to_ohlc(result)
        return { error: "Failed to convert data to OHLC format" } if ohlc_data.nil? || ohlc_data.empty?

        analysis = Analysis::TrendAnalyzer.analyze(ohlc_data)
        return { error: "Analysis returned empty result" } if analysis.nil? || analysis.empty?

        {
          symbol: symbol,
          analysis: analysis,
          interpretation: interpret_for_swing(analysis)
        }
      end

      def calculate_swing_score(analysis)
        details = calculate_swing_score_details(analysis)
        details.values.sum
      end

      def calculate_swing_score_details(analysis)
        return { trend: 0, rsi: 0, macd: 0, structure: 0, patterns: 0 } if analysis.nil? || analysis.empty?

        details = { trend: 0, rsi: 0, macd: 0, structure: 0, patterns: 0 }

        # Trend strength (0-30 points)
        trend = analysis[:trend]
        details[:trend] = (trend[:strength] || 0).clamp(0, 30) if trend && trend[:trend] == :uptrend

        # RSI (0-20 points) - prefer 40-60 for swing entries
        rsi = analysis[:indicators]&.dig(:rsi)
        if rsi
          if rsi.between?(40, 60)
            details[:rsi] = 20
          elsif rsi.between?(30, 70)
            details[:rsi] = 10
          end
        end

        # MACD (0-20 points) - bullish crossover
        macd = analysis[:indicators]&.dig(:macd)
        signal = analysis[:indicators]&.dig(:macd_signal)
        if macd && signal && macd > signal
          details[:macd] = 20
        elsif macd && signal && macd > signal * 0.9
          details[:macd] = 10
        end

        # Structure break (0-15 points)
        structure_break = analysis[:structure_break]
        if structure_break && structure_break[:broken] && structure_break[:direction] == :bullish_break
          details[:structure] = 15
        end

        # Patterns (0-15 points)
        patterns = analysis[:patterns]&.dig(:candlestick) || []
        bullish_patterns = patterns.count { |p| p.is_a?(Hash) && p[:type].to_s.include?("bullish") }
        details[:patterns] = [bullish_patterns * 5, 15].min

        details
      end

      def interpret_for_swing(analysis)
        return "Unable to analyze" if analysis.nil? || analysis.empty?

        trend = analysis[:trend]&.dig(:trend)
        rsi = analysis[:indicators]&.dig(:rsi)
        structure_break = analysis[:structure_break]

        if trend == :uptrend && rsi && rsi < 70 && structure_break && structure_break[:broken]
          "Strong swing candidate - uptrend with bullish structure break"
        elsif trend == :uptrend && rsi && rsi.between?(40, 60)
          "Good swing candidate - healthy uptrend, RSI in good zone"
        else
          "Moderate candidate - review individual factors"
        end
      end

      def convert_to_ohlc(historical_data)
        return [] unless historical_data.is_a?(Hash)

        # Navigate to the actual data: result -> result -> data
        outer_result = historical_data[:result] || historical_data["result"]
        return [] unless outer_result.is_a?(Hash)

        data = outer_result[:data] || outer_result["data"]
        return [] unless data

        # Handle DhanHQ format: {open: [...], high: [...], low: [...], close: [...], volume: [...]}
        if data.is_a?(Hash)
          opens = data[:open] || data["open"] || []
          highs = data[:high] || data["high"] || []
          lows = data[:low] || data["low"] || []
          closes = data[:close] || data["close"] || []
          volumes = data[:volume] || data["volume"] || []

          return [] if closes.empty?

          # Convert parallel arrays to array of hashes
          max_length = [opens.length, highs.length, lows.length, closes.length].max
          ohlc_data = []

          (0...max_length).each do |i|
            ohlc_data << {
              open: opens[i],
              high: highs[i],
              low: lows[i],
              close: closes[i],
              volume: volumes[i] || 0
            }
          end

          return ohlc_data
        end

        # Handle array format: [{open, high, low, close, volume}, ...]
        if data.is_a?(Array)
          return data.map do |bar|
            {
              open: bar["open"] || bar[:open],
              high: bar["high"] || bar[:high],
              low: bar["low"] || bar[:low],
              close: bar["close"] || bar[:close],
              volume: bar["volume"] || bar[:volume]
            }
          end.compact
        end

        []
      end
    end
  end
end

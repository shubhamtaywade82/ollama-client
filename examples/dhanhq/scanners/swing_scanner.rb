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
            puts "         Breakdown: #{format_score_breakdown(r[:details])}" if r[:details]
          end
        end

        candidates.sort_by { |c| -c[:score] }
      end

      def scan_by_criteria(_criteria = {})
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
        return empty_score_details if analysis.nil? || analysis.empty?

        {
          trend: trend_points(analysis),
          rsi: rsi_points(analysis),
          macd: macd_points(analysis),
          structure: structure_points(analysis),
          patterns: pattern_points(analysis)
        }
      end

      def interpret_for_swing(analysis)
        return "Unable to analyze" if analysis.nil? || analysis.empty?

        trend = analysis[:trend]&.dig(:trend)
        rsi = analysis[:indicators]&.dig(:rsi)
        structure_break = analysis[:structure_break]

        if trend == :uptrend && rsi && rsi < 70 && structure_break && structure_break[:broken]
          "Strong swing candidate - uptrend with bullish structure break"
        elsif trend == :uptrend && rsi&.between?(40, 60)
          "Good swing candidate - healthy uptrend, RSI in good zone"
        else
          "Moderate candidate - review individual factors"
        end
      end

      def convert_to_ohlc(historical_data)
        return [] unless historical_data.is_a?(Hash)

        data = extract_data_payload(historical_data)
        return [] unless data

        return ohlc_from_hash(data) if data.is_a?(Hash)
        return ohlc_from_array(data) if data.is_a?(Array)

        []
      end

      def format_score_breakdown(details)
        "Trend=#{details[:trend]}, RSI=#{details[:rsi]}, MACD=#{details[:macd]}, " \
          "Structure=#{details[:structure]}, Patterns=#{details[:patterns]}"
      end

      def empty_score_details
        { trend: 0, rsi: 0, macd: 0, structure: 0, patterns: 0 }
      end

      def trend_points(analysis)
        trend = analysis[:trend]
        return 0 unless trend && trend[:trend] == :uptrend

        (trend[:strength] || 0).clamp(0, 30)
      end

      def rsi_points(analysis)
        rsi = analysis[:indicators]&.dig(:rsi)
        return 0 unless rsi
        return 20 if rsi.between?(40, 60)
        return 10 if rsi.between?(30, 70)

        0
      end

      def macd_points(analysis)
        macd = analysis[:indicators]&.dig(:macd)
        signal = analysis[:indicators]&.dig(:macd_signal)
        return 0 unless macd && signal

        return 20 if macd > signal
        return 10 if macd > signal * 0.9

        0
      end

      def structure_points(analysis)
        structure_break = analysis[:structure_break]
        return 0 unless structure_break && structure_break[:broken]
        return 0 unless structure_break[:direction] == :bullish_break

        15
      end

      def pattern_points(analysis)
        patterns = analysis[:patterns]&.dig(:candlestick) || []
        bullish_patterns = patterns.count { |pattern| pattern.is_a?(Hash) && pattern[:type].to_s.include?("bullish") }
        [bullish_patterns * 5, 15].min
      end

      def extract_data_payload(historical_data)
        outer_result = historical_data[:result] || historical_data["result"]
        return nil unless outer_result.is_a?(Hash)

        outer_result[:data] || outer_result["data"]
      end

      def ohlc_from_hash(data)
        series = extract_series(data)
        return [] if series[:closes].empty?

        max_length = series_lengths(series).max
        build_ohlc_rows(series, max_length)
      end

      def extract_series(data)
        {
          opens: data[:open] || data["open"] || [],
          highs: data[:high] || data["high"] || [],
          lows: data[:low] || data["low"] || [],
          closes: data[:close] || data["close"] || [],
          volumes: data[:volume] || data["volume"] || []
        }
      end

      def series_lengths(series)
        [series[:opens].length, series[:highs].length, series[:lows].length, series[:closes].length]
      end

      def build_ohlc_rows(series, max_length)
        (0...max_length).map do |index|
          {
            open: series[:opens][index],
            high: series[:highs][index],
            low: series[:lows][index],
            close: series[:closes][index],
            volume: series[:volumes][index] || 0
          }
        end
      end

      def ohlc_from_array(data)
        data.filter_map { |bar| normalize_bar(bar) }
      end

      def normalize_bar(bar)
        return nil unless bar.is_a?(Hash)

        {
          open: bar["open"] || bar[:open],
          high: bar["high"] || bar[:high],
          low: bar["low"] || bar[:low],
          close: bar["close"] || bar[:close],
          volume: bar["volume"] || bar[:volume]
        }
      end
    end
  end
end

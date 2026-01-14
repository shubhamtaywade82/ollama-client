# frozen_string_literal: true

require_relative "../analysis/trend_analyzer"
require_relative "../services/data_service"

module DhanHQ
  module Scanners
    # Scanner for intraday options buying opportunities
    class IntradayOptionsScanner
      def initialize
        @data_service = Services::DataService.new
      end

      def scan_for_options_setups(underlying_symbol, exchange_segment: "IDX_I", min_score: 50, verbose: false)
        puts "      🔍 Analyzing underlying: #{underlying_symbol} (#{exchange_segment})" if verbose

        # Analyze underlying
        underlying_analysis = analyze_underlying(underlying_symbol, exchange_segment)
        if underlying_analysis[:error]
          return error_result("Failed to analyze underlying: #{underlying_analysis[:error]}", verbose)
        end

        puts "      ✅ Underlying analysis complete" if verbose

        # Get option chain - first get expiry list, then fetch chain for first expiry
        expiry_list_result = get_option_chain(underlying_symbol, exchange_segment)
        if expiry_list_result[:error]
          return error_result("Failed to get expiry list: #{expiry_list_result[:error]}", verbose)
        end

        expiries = extract_expiries(expiry_list_result)
        return error_result("No expiries found in option chain", verbose) unless expiries

        # Get chain for first expiry (next expiry)
        next_expiry = expiries.first
        puts "      ✅ Found #{expiries.length} expiries, fetching chain for: #{next_expiry}" if verbose

        option_chain = get_option_chain(underlying_symbol, exchange_segment, expiry: next_expiry)
        if option_chain[:error]
          return error_result("Failed to get option chain for expiry #{next_expiry}: #{option_chain[:error]}", verbose)
        end

        puts "      ✅ Option chain retrieved for expiry: #{next_expiry}" if verbose

        # Find best options setups
        setups = find_options_setups(underlying_analysis[:analysis], option_chain, min_score: min_score,
                                                                                   verbose: verbose)

        {
          underlying: underlying_symbol,
          underlying_analysis: underlying_analysis[:analysis],
          setups: setups
        }
      end

      private

      def analyze_underlying(symbol, exchange_segment)
        result = @data_service.execute(
          action: "get_historical_data",
          params: {
            "symbol" => symbol,
            "exchange_segment" => exchange_segment,
            "from_date" => (Date.today - 30).strftime("%Y-%m-%d"),
            "to_date" => Date.today.strftime("%Y-%m-%d"),
            "interval" => "5" # 5-minute for intraday
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
          analysis: analysis
        }
      end

      def get_option_chain(symbol, exchange_segment, expiry: nil)
        @data_service.execute(
          action: "get_option_chain",
          params: {
            "symbol" => symbol,
            "exchange_segment" => exchange_segment,
            "expiry" => expiry
          }
        )
      end

      def find_options_setups(analysis, option_chain, min_score: 50, verbose: false)
        tracking = {
          setups: [],
          rejected: [],
          strikes_evaluated: 0,
          strikes_within_range: 0
        }

        log_underlying_analysis(analysis, verbose)
        log_option_chain_debug(option_chain, verbose)

        chain = extract_option_chain(option_chain, verbose)
        return [] unless chain

        context = build_analysis_context(analysis)
        log_chain_summary(chain, context[:trend], verbose)

        evaluation_context = {
          tracking: tracking,
          context: context,
          min_score: min_score,
          verbose: verbose
        }

        chain.each do |strike_key, strike_data|
          strike = strike_key.to_f
          next unless strike_within_range?(strike, context[:current_price])

          tracking[:strikes_within_range] += 1
          tracking[:strikes_evaluated] += 1

          evaluate_strike_options(
            strike: strike,
            strike_data: strike_data,
            evaluation_context: evaluation_context
          )
        end

        log_evaluation_summary(tracking, context, min_score, verbose)

        tracking[:setups].sort_by { |setup| -setup[:score] }.first(5)
      end

      def calculate_options_score(option_data, context)
        score = 0
        score += implied_volatility_points(option_data[:implied_volatility])
        score += open_interest_points(option_data[:open_interest])
        score += volume_points(option_data[:volume])
        score += trend_points(option_data[:type], context[:trend], context[:relative_strength_index])
        score += rsi_points(option_data[:type], context[:relative_strength_index])
        score
      end

      def implied_volatility_points(implied_volatility)
        return 0 unless implied_volatility

        return 30 if implied_volatility < 15
        return 20 if implied_volatility < 25
        return 10 if implied_volatility < 35

        0
      end

      def open_interest_points(open_interest)
        return 0 unless open_interest
        return 25 if open_interest > 1_000_000
        return 15 if open_interest > 500_000
        return 10 if open_interest > 100_000

        0
      end

      def volume_points(volume)
        return 0 unless volume
        return 20 if volume > 10_000
        return 10 if volume > 5_000

        0
      end

      def trend_points(option_type, trend, relative_strength_index)
        return 0 unless trend
        return 15 if trend_alignment?(option_type, trend)
        return 0 unless trend == :sideways

        rsi_bias_points(option_type, relative_strength_index)
      end

      def trend_alignment?(option_type, trend)
        (option_type == :call && trend == :uptrend) || (option_type == :put && trend == :downtrend)
      end

      def rsi_bias_points(option_type, relative_strength_index)
        return 0 unless relative_strength_index
        return 10 if option_type == :call && relative_strength_index > 50
        return 10 if option_type == :put && relative_strength_index < 50

        0
      end

      def rsi_points(option_type, relative_strength_index)
        return 0 unless relative_strength_index
        return 10 if option_type == :call && relative_strength_index.between?(50, 70)
        return 10 if option_type == :put && relative_strength_index.between?(30, 50)

        0
      end

      def error_result(message, verbose)
        puts "      ⚠️  #{message}" if verbose
        { error: message }
      end

      def extract_expiries(expiry_list_result)
        expiry_list = expiry_list_result[:result] || expiry_list_result["result"]
        return nil unless expiry_list.is_a?(Hash)

        expiries = expiry_list[:expiries] || expiry_list["expiries"]
        return nil unless expiries.is_a?(Array) && expiries.any?

        expiries
      end

      def log_underlying_analysis(analysis, verbose)
        return unless verbose

        puts "      📊 Underlying Analysis:"
        return puts("         ⚠️  Analysis data not available") unless analysis && !analysis.empty?

        current_price = analysis[:current_price]
        trend = analysis[:trend]&.dig(:trend)
        relative_strength_index = analysis[:indicators]&.dig(:rsi)
        puts "         Current Price: #{current_price || 'N/A'}"
        puts "         Trend: #{trend || 'N/A'}"
        puts "         RSI: #{relative_strength_index&.round(2) || 'N/A'}"
      end

      def log_option_chain_debug(option_chain, verbose)
        return unless verbose

        puts "      🔍 Option chain structure:"
        return unless option_chain.is_a?(Hash)

        puts "         Keys: #{option_chain.keys.inspect}"
        puts "         Has result?: #{option_chain.key?(:result) || option_chain.key?('result')}"
        result = option_chain[:result] || option_chain["result"]
        return unless result.is_a?(Hash)

        puts "         Result keys: #{result.keys.inspect}"
        puts "         Has chain?: #{result.key?(:chain) || result.key?('chain')}"
        puts "         Has expiries?: #{result.key?(:expiries) || result.key?('expiries')}"
      end

      def extract_option_chain(option_chain, verbose)
        result = option_chain[:result] || option_chain["result"]
        unless result
          puts "      ⚠️  Option chain data not available or invalid (no result)" if verbose
          return nil
        end

        chain = result[:chain] || result["chain"]
        return chain if chain

        return nil unless verbose

        puts "      ⚠️  Option chain data not available or invalid (no chain in result)"
        puts "         Available keys in result: #{result.keys.inspect}" if result.is_a?(Hash)
        puts "         Result structure: #{result.inspect[0..200]}"
        nil
      end

      def build_analysis_context(analysis)
        return { current_price: nil, trend: nil, relative_strength_index: nil } unless analysis

        {
          current_price: analysis[:current_price],
          trend: analysis[:trend]&.dig(:trend),
          relative_strength_index: analysis[:indicators]&.dig(:rsi)
        }
      end

      def log_chain_summary(chain, trend, verbose)
        return unless verbose

        puts "         Chain strikes: #{chain.keys.length}"
        puts "         Looking for: #{preferred_option_label(trend)}"
      end

      def preferred_option_label(trend)
        return "CALL options" if trend == :uptrend
        return "PUT options" if trend == :downtrend

        "CALL or PUT (sideways trend)"
      end

      def strike_within_range?(strike, current_price)
        return false unless current_price

        (strike - current_price).abs / current_price < 0.02
      end

      def evaluate_strike_options(strike:, strike_data:, evaluation_context:)
        context = evaluation_context[:context]

        call_data = strike_data["ce"] || strike_data[:ce]
        put_data = strike_data["pe"] || strike_data[:pe]

        if call_data && option_allowed?(:call, context[:trend])
          evaluate_option_setup(
            option_type: :call,
            strike: strike,
            raw_data: call_data,
            evaluation_context: evaluation_context
          )
        end

        return unless put_data && option_allowed?(:put, context[:trend])

        evaluate_option_setup(
          option_type: :put,
          strike: strike,
          raw_data: put_data,
          evaluation_context: evaluation_context
        )
      end

      def option_allowed?(option_type, trend)
        return %i[uptrend sideways].include?(trend) if option_type == :call
        return %i[downtrend sideways].include?(trend) if option_type == :put

        false
      end

      def evaluate_option_setup(option_type:, strike:, raw_data:, evaluation_context:)
        tracking = evaluation_context[:tracking]
        context = evaluation_context[:context]
        min_score = evaluation_context[:min_score]
        verbose = evaluation_context[:verbose]

        option_data = option_data_for(option_type, raw_data)
        score = calculate_options_score(option_data, context)

        if score >= min_score
          tracking[:setups] << build_setup(option_data, strike, score)
          return
        end

        return unless verbose

        tracking[:rejected] << {
          type: option_type,
          strike: strike,
          score: score,
          reason: "Below min_score (#{min_score})"
        }
      end

      def option_data_for(option_type, raw_data)
        {
          type: option_type,
          implied_volatility: raw_data["implied_volatility"] || raw_data[:implied_volatility],
          open_interest: raw_data["oi"] || raw_data[:oi],
          volume: raw_data["volume"] || raw_data[:volume],
          last_price: raw_data["last_price"] || raw_data[:last_price] || raw_data["ltp"] || raw_data[:ltp]
        }
      end

      def build_setup(option_data, strike, score)
        {
          type: option_data[:type],
          strike: strike,
          iv: option_data[:implied_volatility],
          oi: option_data[:open_interest],
          volume: option_data[:volume],
          ltp: option_data[:last_price],
          score: score,
          recommendation: recommendation_for_score(score)
        }
      end

      def recommendation_for_score(score)
        return "Strong buy" if score > 70
        return "Moderate buy" if score > 50

        "Weak"
      end

      def log_evaluation_summary(tracking, context, min_score, verbose)
        return unless verbose

        puts "      📊 Evaluation Summary:"
        puts "         Strikes within 2% of price: #{tracking[:strikes_within_range]}"
        puts "         Strikes evaluated: #{tracking[:strikes_evaluated]}"
        puts "         Setups found: #{tracking[:setups].length}"

        if tracking[:rejected].any?
          log_rejected_setups(tracking[:rejected], min_score)
        elsif tracking[:strikes_evaluated].zero?
          log_no_strike_message(tracking, context)
        end
      end

      def log_rejected_setups(rejected, min_score)
        puts "      📋 Rejected setups: #{rejected.length} (below min_score #{min_score})"
        rejected.first(5).each do |rejection|
          puts "         ❌ #{rejection[:type].to_s.upcase} @ #{rejection[:strike]}: Score #{rejection[:score]}/100"
        end
      end

      def log_no_strike_message(tracking, context)
        trend = context[:trend]
        current_price = context[:current_price]

        if !trend || trend == :sideways
          puts "      ⚠️  Sideways trend - no clear directional bias for calls/puts"
        elsif trend == :uptrend && tracking[:strikes_within_range].zero?
          puts "      ⚠️  No CALL strikes found within 2% of current price (#{current_price})"
        elsif trend == :downtrend && tracking[:strikes_within_range].zero?
          puts "      ⚠️  No PUT strikes found within 2% of current price (#{current_price})"
        else
          puts "      ⚠️  No suitable strikes found for current trend (#{trend || 'unknown'})"
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

      def extract_data_payload(historical_data)
        outer_result = historical_data[:result] || historical_data["result"]
        return nil unless outer_result.is_a?(Hash)

        outer_result[:data] || outer_result["data"]
      end

      def ohlc_from_hash(data)
        series = extract_series(data)
        return [] if series[:closes].nil? || series[:closes].empty?

        max_length = series_lengths(series).max
        return [] if max_length.zero?

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
            open: series[:opens][index] || series[:closes][index] || 0,
            high: series[:highs][index] || series[:closes][index] || 0,
            low: series[:lows][index] || series[:closes][index] || 0,
            close: series[:closes][index] || 0,
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

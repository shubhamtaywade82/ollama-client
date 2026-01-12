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
          error_msg = "Failed to analyze underlying: #{underlying_analysis[:error]}"
          puts "      ⚠️  #{error_msg}" if verbose
          return { error: error_msg }
        end

        puts "      ✅ Underlying analysis complete" if verbose

        # Get option chain - first get expiry list, then fetch chain for first expiry
        expiry_list_result = get_option_chain(underlying_symbol, exchange_segment)
        if expiry_list_result[:error]
          error_msg = "Failed to get expiry list: #{expiry_list_result[:error]}"
          puts "      ⚠️  #{error_msg}" if verbose
          return { error: error_msg }
        end

        # Extract expiry list
        expiry_list = expiry_list_result[:result] || expiry_list_result["result"]
        expiries = expiry_list[:expiries] || expiry_list["expiries"] if expiry_list.is_a?(Hash)

        unless expiries && expiries.is_a?(Array) && !expiries.empty?
          error_msg = "No expiries found in option chain"
          puts "      ⚠️  #{error_msg}" if verbose
          return { error: error_msg }
        end

        # Get chain for first expiry (next expiry)
        next_expiry = expiries.first
        puts "      ✅ Found #{expiries.length} expiries, fetching chain for: #{next_expiry}" if verbose

        option_chain = get_option_chain(underlying_symbol, exchange_segment, expiry: next_expiry)
        if option_chain[:error]
          error_msg = "Failed to get option chain for expiry #{next_expiry}: #{option_chain[:error]}"
          puts "      ⚠️  #{error_msg}" if verbose
          return { error: error_msg }
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
        setups = []
        rejected = []
        strikes_evaluated = 0
        strikes_within_range = 0

        if verbose
          puts "      📊 Underlying Analysis:"
          if analysis && !analysis.empty?
            current_price = analysis[:current_price]
            trend = analysis[:trend]&.dig(:trend)
            rsi = analysis[:indicators]&.dig(:rsi)
            puts "         Current Price: #{current_price || 'N/A'}"
            puts "         Trend: #{trend || 'N/A'}"
            puts "         RSI: #{rsi&.round(2) || 'N/A'}"
          else
            puts "         ⚠️  Analysis data not available"
          end
        end

        # Debug: Check the structure
        if verbose
          puts "      🔍 Option chain structure:"
          puts "         Keys: #{option_chain.keys.inspect}" if option_chain.is_a?(Hash)
          puts "         Has result?: #{option_chain.key?(:result) || option_chain.key?('result')}"
          if option_chain[:result] || option_chain["result"]
            result = option_chain[:result] || option_chain["result"]
            puts "         Result keys: #{result.keys.inspect}" if result.is_a?(Hash)
            puts "         Has chain?: #{result.key?(:chain) || result.key?('chain')}"
            puts "         Has expiries?: #{result.key?(:expiries) || result.key?('expiries')}"
          end
        end

        # Extract chain from result
        result = option_chain[:result] || option_chain["result"]

        unless result
          puts "      ⚠️  Option chain data not available or invalid (no result)" if verbose
          return setups
        end

        chain = result[:chain] || result["chain"]

        unless chain
          puts "      ⚠️  Option chain data not available or invalid (no chain in result)" if verbose
          if verbose
            puts "         Available keys in result: #{result.keys.inspect}" if result.is_a?(Hash)
            puts "         Result structure: #{result.inspect[0..200]}"
          end
          return setups
        end
        current_price = analysis[:current_price] if analysis
        trend = analysis[:trend]&.dig(:trend) if analysis
        rsi = analysis[:indicators]&.dig(:rsi) if analysis

        if verbose
          puts "         Chain strikes: #{chain.keys.length}"
          puts "         Looking for: #{if trend == :uptrend
                                          'CALL options'
                                        else
                                          trend == :downtrend ? 'PUT options' : 'CALL or PUT (sideways trend)'
                                        end}"
        end

        # For intraday options buying:
        # - Look for ATM or near-ATM strikes
        # - Prefer calls in uptrend, puts in downtrend
        # - Consider IV (lower is better for buying)
        # - Look for high volume/OI

        chain.each do |strike_str, strike_data|
          strike = strike_str.to_f
          price_diff_pct = ((strike - current_price).abs / current_price * 100).round(2)

          next unless (strike - current_price).abs / current_price < 0.02 # Within 2% of current price

          strikes_within_range += 1

          strikes_evaluated += 1

          ce_data = strike_data["ce"] || strike_data[:ce]
          pe_data = strike_data["pe"] || strike_data[:pe]

          # Evaluate CALL options
          if ce_data && (trend == :uptrend || trend == :sideways)
            iv = ce_data["implied_volatility"] || ce_data[:implied_volatility]
            oi = ce_data["oi"] || ce_data[:oi]
            volume = ce_data["volume"] || ce_data[:volume]

            score = calculate_options_score(iv, oi, volume, :call, trend, rsi)
            if score >= min_score
              setups << {
                type: :call,
                strike: strike,
                iv: iv,
                oi: oi,
                volume: volume,
                score: score,
                recommendation: if score > 70
                                  "Strong buy"
                                else
                                  score > 50 ? "Moderate buy" : "Weak"
                                end
              }
            elsif verbose
              rejected << { type: :call, strike: strike, score: score, reason: "Below min_score (#{min_score})" }
            end
          end

          # Evaluate PUT options
          if pe_data && (trend == :downtrend || trend == :sideways)
            iv = pe_data["implied_volatility"] || pe_data[:implied_volatility]
            oi = pe_data["oi"] || pe_data[:oi]
            volume = pe_data["volume"] || pe_data[:volume]

            score = calculate_options_score(iv, oi, volume, :put, trend, rsi)
            if score >= min_score
              setups << {
                type: :put,
                strike: strike,
                iv: iv,
                oi: oi,
                volume: volume,
                score: score,
                recommendation: if score > 70
                                  "Strong buy"
                                else
                                  score > 50 ? "Moderate buy" : "Weak"
                                end
              }
            elsif verbose
              rejected << { type: :put, strike: strike, score: score, reason: "Below min_score (#{min_score})" }
            end
          end
        end

        if verbose
          puts "      📊 Evaluation Summary:"
          puts "         Strikes within 2% of price: #{strikes_within_range}"
          puts "         Strikes evaluated: #{strikes_evaluated}"
          puts "         Setups found: #{setups.length}"

          if !rejected.empty?
            puts "      📋 Rejected setups: #{rejected.length} (below min_score #{min_score})"
            rejected.first(5).each do |r|
              puts "         ❌ #{r[:type].to_s.upcase} @ #{r[:strike]}: Score #{r[:score]}/100"
            end
          elsif strikes_evaluated == 0
            if !trend || trend == :sideways
              puts "      ⚠️  Sideways trend - no clear directional bias for calls/puts"
            elsif trend == :uptrend && strikes_within_range == 0
              puts "      ⚠️  No CALL strikes found within 2% of current price (#{current_price})"
            elsif trend == :downtrend && strikes_within_range == 0
              puts "      ⚠️  No PUT strikes found within 2% of current price (#{current_price})"
            elsif strikes_within_range > 0 && strikes_evaluated == 0
              puts "      ⚠️  Found #{strikes_within_range} strikes within range, but none match trend criteria"
              puts "         (Trend: #{trend}, looking for #{trend == :uptrend ? 'CALL' : 'PUT'} options)"
            else
              puts "      ⚠️  No suitable strikes found for current trend (#{trend || 'unknown'})"
            end
          end
        end

        setups.sort_by { |s| -s[:score] }.first(5) # Top 5 setups
      end

      def calculate_options_score(iv, oi, volume, option_type, trend, rsi)
        score = 0

        # IV scoring (lower is better for buying) - 0-30 points
        if iv
          if iv < 15
            score += 30
          elsif iv < 25
            score += 20
          elsif iv < 35
            score += 10
          end
        end

        # OI scoring (higher is better) - 0-25 points
        if oi && oi > 1_000_000
          score += 25
        elsif oi && oi > 500_000
          score += 15
        elsif oi && oi > 100_000
          score += 10
        end

        # Volume scoring - 0-20 points
        if volume && volume > 10_000
          score += 20
        elsif volume && volume > 5_000
          score += 10
        end

        # Trend alignment - 0-15 points
        if trend == :sideways
          # In sideways markets, use RSI to bias scoring
          if option_type == :call && rsi && rsi > 50
            score += 10 # Slight bias toward calls if RSI > 50
          elsif option_type == :put && rsi && rsi < 50
            score += 10 # Slight bias toward puts if RSI < 50
          end
        else
          score += 15 if (option_type == :call && trend == :uptrend) || (option_type == :put && trend == :downtrend)
        end

        # RSI alignment - 0-10 points
        if rsi
          if option_type == :call && rsi < 70 && rsi > 50
            score += 10
          elsif option_type == :put && rsi > 30 && rsi < 50
            score += 10
          end
        end

        score
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

          return [] if closes.nil? || closes.empty?

          # Convert parallel arrays to array of hashes
          max_length = [opens.length, highs.length, lows.length, closes.length].max
          return [] if max_length.zero?

          ohlc_data = []

          (0...max_length).each do |i|
            ohlc_data << {
              open: opens[i] || closes[i] || 0,
              high: highs[i] || closes[i] || 0,
              low: lows[i] || closes[i] || 0,
              close: closes[i] || 0,
              volume: volumes[i] || 0
            }
          end

          return ohlc_data
        end

        # Handle array format: [{open, high, low, close, volume}, ...]
        if data.is_a?(Array)
          return data.map do |bar|
            next nil unless bar.is_a?(Hash)

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

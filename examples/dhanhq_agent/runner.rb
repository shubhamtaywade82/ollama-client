# frozen_string_literal: true

require "date"
require "json"
require "dhan_hq"

require_relative "../../lib/ollama_client"
require_relative "../dhanhq_tools"
require_relative "agents/data_agent"
require_relative "agents/trading_agent"
require_relative "market_context_builder"

module DhanHQAgent
  class Runner
    def self.run
      new.run
    end

    def run
      configure_dhanhq
      print_header

      run_data_agent_demo
      run_trading_agent_demo

      print_summary
    end

    private

    def configure_dhanhq
      DhanHQ.configure_with_env
      puts "✅ DhanHQ configured"
    rescue StandardError => e
      puts "⚠️  DhanHQ configuration error: #{e.message}"
      puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
      puts "   Continuing with mock data for demonstration..."
    end

    def print_header
      puts "=" * 60
      puts "DhanHQ Agent: Ollama (Reasoning) + DhanHQ (Data & Trading)"
      puts "=" * 60
      puts
    end

    def run_data_agent_demo
      puts "─" * 60
      puts "DATA AGENT: Market Data Retrieval"
      puts "─" * 60
      puts

      data_agent = Agents::DataAgent.new(ollama_client: Ollama::Client.new)

      run_data_agent_market_analysis(data_agent)
      run_data_agent_all_data_apis_demo
    end

    def run_data_agent_market_analysis(data_agent)
      puts "Example 1: Market Analysis & Data Decision (Real Data)"
      puts "─" * 60

      puts "📊 Fetching real market data from DhanHQ..."

      market_data = fetch_market_data
      market_context = MarketContextBuilder.build(market_data)

      puts
      puts "Market Context (from real data):"
      puts market_context
      puts

      analyze_and_execute_data_decision(data_agent, market_context)
      puts
    end

    def analyze_and_execute_data_decision(data_agent, market_context)
      puts "🤔 Analyzing market with Ollama..."
      decision = data_agent.analyze_and_decide(market_context: market_context)

      puts "\n📋 Decision:"
      print_decision(decision)

      return if decision_action(decision) == "no_action"

      puts "\n⚡ Executing data retrieval..."
      result = data_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
    rescue Ollama::Error => e
      puts "❌ Error: #{e.message}"
    end

    def print_decision(decision)
      unless decision.is_a?(Hash)
        puts "   ⚠️  Invalid decision returned: #{decision.inspect}"
        return
      end

      puts "   Action: #{decision_value(decision, "action") || 'N/A'}"
      puts "   Reasoning: #{decision_value(decision, "reasoning") || 'N/A'}"

      confidence = decision_value(decision, "confidence")
      if confidence
        puts "   Confidence: #{(confidence * 100).round}%"
      else
        puts "   Confidence: N/A"
      end

      puts "   Parameters: #{JSON.pretty_generate(decision_value(decision, "parameters") || {})}"
    end

    def fetch_market_data
      market_data = {}

      market_data[:nifty] = fetch_live_ltp(symbol: "NIFTY", exchange_segment: "IDX_I", label: "NIFTY")
      market_data[:reliance] = fetch_live_ltp(symbol: "RELIANCE", exchange_segment: "NSE_EQ", label: "RELIANCE")
      market_data[:positions] = fetch_positions

      market_data
    end

    def fetch_live_ltp(symbol:, exchange_segment:, label:)
      result = DhanHQDataTools.get_live_ltp(symbol: symbol, exchange_segment: exchange_segment)
      sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs

      if result.is_a?(Hash) && result[:error]
        print_data_api_error(label, result[:error])
        return nil
      end

      unless result.is_a?(Hash) && result[:result]
        print_no_data(label)
        return nil
      end

      print_ltp_result(label, result[:result])
      result[:result]
    rescue StandardError => e
      puts "  ⚠️  #{label} data error: #{e.message}"
      nil
    end

    def print_ltp_result(label, instrument_data)
      ltp = instrument_data[:ltp]
      if ltp && ltp != 0
        puts "  ✅ #{label}: LTP=#{ltp}"
        return
      end

      puts "  ⚠️  #{label}: Data retrieved but LTP is null/empty (may be outside market hours)"
      puts "     Result: #{JSON.pretty_generate(instrument_data)}"
    end

    def print_data_api_error(label, error_message)
      puts "  ⚠️  #{label} data error: #{error_message}"
    end

    def print_no_data(label)
      puts "  ⚠️  #{label}: No data returned"
    end

    def fetch_positions
      # NOTE: Positions and holdings are not part of the 6 Data APIs
      positions_result = {
        action: "check_positions",
        result: { positions: [], count: 0 },
        note: "Positions API not available in Data Tools"
      }

      if positions_result[:result]
        puts "  ✅ Positions: #{positions_result[:result][:count] || 0} active"
        return positions_result[:result][:positions] || []
      end

      puts "  ✅ Positions: 0 active (Positions API not in Data Tools)"
      []
    rescue StandardError => e
      puts "  ⚠️  Positions error: #{e.message}"
      []
    end

    def run_data_agent_all_data_apis_demo
      puts "─" * 60
      puts "Example 2: All Data APIs Demonstration"
      puts "─" * 60
      puts "Demonstrating all available DhanHQ Data APIs:"
      puts

      test_symbol = "RELIANCE" # RELIANCE symbol for Instrument.find
      test_exchange = "NSE_EQ"

      demonstrate_market_quote(test_symbol, test_exchange)
      demonstrate_ltp(test_symbol, test_exchange)
      demonstrate_market_depth(test_symbol, test_exchange)
      demonstrate_historical_data(test_symbol, test_exchange)
      demonstrate_expired_options_data
      demonstrate_option_chain
      puts
    end

    def demonstrate_market_quote(symbol, exchange)
      puts "1️⃣  Market Quote API"
      result = DhanHQDataTools.get_market_quote(symbol: symbol, exchange_segment: exchange)
      if result[:result]
        puts "   ✅ Market Quote retrieved"
        puts "   📊 Quote data: #{JSON.pretty_generate(result[:result][:quote])}"
      else
        puts "   ⚠️  #{result[:error]}"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    ensure
      puts
      sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs
    end

    def demonstrate_ltp(symbol, exchange)
      puts "2️⃣  Live Market Feed API (LTP)"
      result = DhanHQDataTools.get_live_ltp(symbol: symbol, exchange_segment: exchange)
      if result[:result]
        puts "   ✅ LTP retrieved"
        puts "   📊 LTP: #{result[:result][:ltp].inspect}"
      else
        puts "   ⚠️  #{result[:error]}"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    ensure
      puts
      sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs
    end

    def demonstrate_market_depth(symbol, exchange)
      puts "3️⃣  Full Market Depth API"
      result = DhanHQDataTools.get_market_depth(symbol: symbol, exchange_segment: exchange)
      if result[:result]
        puts "   ✅ Market Depth retrieved"
        puts "   📊 Buy depth: #{result[:result][:buy_depth]&.length || 0} levels"
        puts "   📊 Sell depth: #{result[:result][:sell_depth]&.length || 0} levels"
        puts "   📊 LTP: #{result[:result][:ltp]}"
        puts "   📊 Volume: #{result[:result][:volume]}"
      else
        puts "   ⚠️  #{result[:error]}"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    ensure
      puts
      sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs
    end

    def demonstrate_historical_data(symbol, exchange)
      puts "4️⃣  Historical Data API"
      to_date = Date.today.strftime("%Y-%m-%d")
      from_date = (Date.today - 30).strftime("%Y-%m-%d")

      result = DhanHQDataTools.get_historical_data(
        symbol: symbol,
        exchange_segment: exchange,
        from_date: from_date,
        to_date: to_date
      )

      if result[:result]
        puts "   ✅ Historical data retrieved"
        puts "   📊 Type: #{result[:type]}"
        puts "   📊 Records: #{result[:result][:count]}"
        if result[:result][:count].zero?
          puts "   ⚠️  No data found for date range #{from_date} to #{to_date}"
          puts "      (This may be normal if market was closed or data unavailable)"
        end
      else
        puts "   ⚠️  #{result[:error]}"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    ensure
      puts
      sleep(0.5) # Small delay for Instrument APIs
    end

    def demonstrate_expired_options_data
      puts "5️⃣  Expired Options Data API"
      result = DhanHQDataTools.get_expired_options_data(
        security_id: "13", # NIFTY security_id (use directly since symbol lookup might fail in NSE_FNO)
        exchange_segment: "NSE_FNO",
        expiry_date: (Date.today - 7).strftime("%Y-%m-%d"),
        instrument: "OPTIDX",
        expiry_flag: "MONTH",
        expiry_code: 1,
        strike: "ATM",
        drv_option_type: "CALL",
        interval: "1"
      )

      if result[:result]
        puts "   ✅ Expired options data retrieved"
        puts "   📊 Expiry: #{result[:result][:expiry_date]}"
        print_expired_options_summary(result[:result])
      else
        puts "   ⚠️  #{result[:error]}"
        puts "      (Note: Options may require specific symbol format or may not exist for this instrument)"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    ensure
      puts
      sleep(0.5) # Small delay for Instrument APIs
    end

    def print_expired_options_summary(expired_options_result)
      stats = expired_options_result[:summary_stats]
      unless stats
        puts "   📊 Data available but summary stats not found"
        return
      end

      concise_summary = {
        data_points: stats[:data_points] || 0,
        avg_volume: stats[:avg_volume]&.round(2),
        avg_open_interest: stats[:avg_open_interest]&.round(2),
        avg_implied_volatility: stats[:avg_implied_volatility]&.round(4),
        price_range_stats: price_range_stats(stats[:price_ranges]),
        has_ohlc: stats[:has_ohlc],
        has_volume: stats[:has_volume],
        has_open_interest: stats[:has_open_interest],
        has_implied_volatility: stats[:has_implied_volatility]
      }

      puts "   📊 Data summary: #{JSON.pretty_generate(concise_summary)}"
    end

    def price_range_stats(price_ranges)
      return nil unless price_ranges.is_a?(Array) && !price_ranges.empty?

      {
        min: price_ranges.min.round(2),
        max: price_ranges.max.round(2),
        avg: (price_ranges.sum / price_ranges.length).round(2),
        count: price_ranges.length
      }
    end

    def demonstrate_option_chain
      puts "6️⃣  Option Chain API"

      expiry_list_result = DhanHQDataTools.get_option_chain(
        symbol: "NIFTY",
        exchange_segment: "IDX_I"
      )

      if expiry_list_result[:result] && expiry_list_result[:result][:expiries]
        expiries = expiry_list_result[:result][:expiries]
        puts "   ✅ Available expiries: #{expiry_list_result[:result][:count]}"
        puts "   📊 First few expiries: #{expiries.first(3).inspect}" if expiries.is_a?(Array) && !expiries.empty?
        demonstrate_option_chain_for_first_expiry(expiries)
      elsif expiry_list_result[:error]
        puts "   ⚠️  #{expiry_list_result[:error]}"
        puts "      (Note: Options may require specific symbol format or may not exist for this instrument)"
      end
    rescue StandardError => e
      puts "   ❌ Error: #{e.message}"
    end

    def demonstrate_option_chain_for_first_expiry(expiries)
      next_expiry = expiries.is_a?(Array) && !expiries.empty? ? expiries.first : nil
      return unless next_expiry

      puts "   📊 Fetching option chain for next expiry: #{next_expiry}"

      chain_result = DhanHQDataTools.get_option_chain(
        symbol: "NIFTY",
        exchange_segment: "IDX_I",
        expiry: next_expiry
      )

      if chain_result[:result] && chain_result[:result][:chain]
        print_option_chain_summary(chain_result[:result])
      elsif chain_result[:error]
        puts "   ⚠️  Could not retrieve option chain data: #{chain_result[:error]}"
      end
    end

    def print_option_chain_summary(result)
      chain = result[:chain]
      underlying_price = result[:underlying_last_price]

      puts "   ✅ Option chain retrieved for expiry: #{result[:expiry]}"
      puts "   📊 Underlying LTP: #{underlying_price}" if underlying_price
      puts "   📊 Chain summary: #{JSON.pretty_generate(option_chain_summary(chain, underlying_price, result[:expiry]))}"
    end

    def option_chain_summary(chain, underlying_price, expiry)
      return { expiry: expiry, chain_type: chain.class } unless chain.is_a?(Hash)

      strike_prices = chain.keys.sort_by(&:to_f)
      first_strike_data = strike_prices.empty? ? nil : chain[strike_prices.first]

      atm_strike = nearest_strike(strike_prices, underlying_price)
      sample_greeks = extract_sample_greeks(chain: chain, strike: atm_strike)

      {
        expiry: expiry,
        underlying_last_price: underlying_price,
        strikes_count: strike_prices.length,
        has_call_options: strike_has_key?(first_strike_data, "ce"),
        has_put_options: strike_has_key?(first_strike_data, "pe"),
        has_greeks: !sample_greeks.empty?,
        strike_range: strike_range(strike_prices),
        sample_greeks: sample_greeks.empty? ? nil : sample_greeks
      }
    end

    def strike_has_key?(strike_data, key)
      strike_data.is_a?(Hash) && (strike_data.key?(key) || strike_data.key?(key.to_sym))
    end

    def strike_range(strike_prices)
      return nil if strike_prices.empty?

      { min: strike_prices.first, max: strike_prices.last, sample_strikes: strike_prices.first(5) }
    end

    def nearest_strike(strike_prices, underlying_price)
      return strike_prices.first if strike_prices.empty?
      return strike_prices.first unless underlying_price

      strike_prices.min_by { |s| (s.to_f - underlying_price).abs }
    end

    def extract_sample_greeks(chain:, strike:)
      return {} unless strike

      strike_data = chain[strike]
      return {} unless strike_data.is_a?(Hash)

      call_data = strike_data["ce"] || strike_data[:ce]
      put_data = strike_data["pe"] || strike_data[:pe]

      sample = {}
      sample[:call] = option_greeks_snapshot(option_data: call_data, strike: strike) if option_has_greeks?(call_data)
      sample[:put] = option_greeks_snapshot(option_data: put_data, strike: strike) if option_has_greeks?(put_data)
      sample
    end

    def option_has_greeks?(option_data)
      option_data.is_a?(Hash) && (option_data.key?("greeks") || option_data.key?(:greeks))
    end

    def option_greeks_snapshot(option_data:, strike:)
      greeks = option_data["greeks"] || option_data[:greeks]
      {
        strike: strike,
        delta: greeks["delta"] || greeks[:delta],
        theta: greeks["theta"] || greeks[:theta],
        gamma: greeks["gamma"] || greeks[:gamma],
        vega: greeks["vega"] || greeks[:vega],
        iv: option_data["implied_volatility"] || option_data[:implied_volatility],
        oi: option_data["oi"] || option_data[:oi],
        last_price: option_data["last_price"] || option_data[:last_price]
      }
    end

    def run_trading_agent_demo
      puts "=" * 60
      puts "TRADING AGENT: Order Parameter Building"
      puts "=" * 60
      puts

      config = Ollama::Config.new
      config.timeout = 60
      trading_ollama_client = Ollama::Client.new(config: config)
      trading_agent = Agents::TradingAgent.new(ollama_client: trading_ollama_client)

      run_simple_buy_order_demo(trading_agent)
      puts
    end

    def run_simple_buy_order_demo(trading_agent)
      puts "Example 1: Simple Buy Order"
      puts "─" * 60

      market_context = <<~CONTEXT
        RELIANCE is showing strong momentum.
        Current LTP: 2,850
        Entry price: 2,850
        Quantity: 100 shares
        Use regular order. security_id="1333", exchange_segment="NSE_EQ"
      CONTEXT

      puts "Market Context:"
      puts market_context
      puts

      puts "🤔 Analyzing with Ollama..."
      decision = trading_agent.analyze_and_decide(market_context: market_context)

      puts "\n📋 Decision:"
      if decision.is_a?(Hash)
        puts "   Action: #{decision['action'] || 'N/A'}"
        puts "   Reasoning: #{decision['reasoning'] || 'N/A'}"
        puts "   Confidence: #{(decision['confidence'] * 100).round}%" if decision["confidence"]
        puts "   Parameters: #{JSON.pretty_generate(decision['parameters'] || {})}"
      end

      return if decision_action(decision) == "no_action"

      puts "\n⚡ Building order parameters (order not placed)..."
      result = trading_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
      print_order_params_hint(result)
    rescue Ollama::TimeoutError => e
      puts "⏱️  Timeout: #{e.message}"
    rescue Ollama::Error => e
      puts "❌ Error: #{e.message}"
    end

    def print_order_params_hint(result)
      return unless result.is_a?(Hash) && result[:order_params]

      puts "\n   📝 Order Parameters Ready:"
      puts "      #{JSON.pretty_generate(result[:order_params])}"
      puts "   💡 To place order: DhanHQ::Models::Order.new(result[:order_params]).save"
    end

    def print_summary
      puts "=" * 60
      puts "DhanHQ Agent Summary:"
      puts "  ✅ Ollama: Reasoning & Decision Making"
      puts "  ✅ DhanHQ: Data Retrieval & Order Building"
      puts "  ✅ Data APIs: Market Quote, Live Market Feed, Full Market Depth, " \
           "Historical Data, Expired Options Data, Option Chain"
      puts "  ✅ Trading Tools: Order parameters, Super order parameters, Cancel parameters"
      puts "  ✅ Instrument Convenience Methods: ltp, ohlc, quote, daily, intraday, expiry_list, option_chain"
      puts "=" * 60
    end

    def decision_action(decision)
      decision_value(decision, "action")
    end

    def decision_value(decision, key)
      return nil unless decision.is_a?(Hash)

      decision[key] || decision[key.to_sym]
    end
  end
end


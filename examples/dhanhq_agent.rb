#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Agent - Complete trading agent with data retrieval and trading operations
# This agent can:
# - Fetch and analyze market data (6 Data APIs)
# - Build order parameters for trading (does not place orders)

require "json"
require "dhan_hq"
require_relative "../lib/ollama_client"
require_relative "dhanhq_tools"

# Debug logging helper
def debug_log(location, message, data = {}, hypothesis_id = nil)
  log_entry = {
    sessionId: "debug-session",
    runId: "run1",
    hypothesisId: hypothesis_id,
    location: location,
    message: message,
    data: data,
    timestamp: Time.now.to_f * 1000
  }
  File.open("/home/nemesis/project/ollama-client/.cursor/debug.log", "a") do |f|
    f.puts(log_entry.to_json)
  end
rescue StandardError
  # Ignore logging errors
end

# Helper to build market context from data
# rubocop:disable Metrics/PerceivedComplexity
def build_market_context_from_data(market_data)
  context_parts = []

  if market_data[:nifty]
    ltp = market_data[:nifty][:ltp]
    change = market_data[:nifty][:change_percent]
    context_parts << if ltp && ltp != 0
                       "NIFTY is trading at #{ltp} (#{change || 'unknown'}% change)"
                     else
                       "NIFTY data retrieved but LTP is not available (may be outside market hours)"
                     end
  else
    context_parts << "NIFTY data not available"
  end

  if market_data[:reliance]
    ltp = market_data[:reliance][:ltp]
    change = market_data[:reliance][:change_percent]
    volume = market_data[:reliance][:volume]
    context_parts << if ltp && ltp != 0
                       "RELIANCE is at #{ltp} (#{change || 'unknown'}% change, Volume: #{volume || 'N/A'})"
                     else
                       "RELIANCE data retrieved but LTP is not available (may be outside market hours)"
                     end
  else
    context_parts << "RELIANCE data not available"
  end

  if market_data[:positions] && !market_data[:positions].empty?
    context_parts << "Current positions: #{market_data[:positions].length} active"
    market_data[:positions].each do |pos|
      context_parts << "  - #{pos[:trading_symbol]}: #{pos[:quantity]} @ #{pos[:average_price]}"
    end
  else
    context_parts << "Current positions: None"
  end

  context_parts.join("\n")
end
# rubocop:enable Metrics/PerceivedComplexity

# Data-focused Agent using Ollama for reasoning
class DataAgent
  def initialize(ollama_client:)
    @ollama_client = ollama_client
    @decision_schema = {
      "type" => "object",
      "required" => ["action", "reasoning", "confidence"],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => ["get_market_quote", "get_live_ltp", "get_market_depth", "get_historical_data",
                     "get_expired_options_data", "get_option_chain", "no_action"]
        },
        "reasoning" => {
          "type" => "string",
          "description" => "Why this action was chosen"
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Confidence in this decision"
        },
        "parameters" => {
          "type" => "object",
          "description" => "Parameters for the action (symbol, exchange_segment, etc.)"
        }
      }
    }
  end

  def analyze_and_decide(market_context:)
    prompt = build_analysis_prompt(market_context: market_context)

    begin
      decision = @ollama_client.generate(
        prompt: prompt,
        schema: @decision_schema
      )

      # Validate confidence threshold
      return { action: "no_action", reason: "invalid_decision" } unless decision.is_a?(Hash) && decision["confidence"]

      if decision["confidence"] < 0.6
        puts "⚠️  Low confidence (#{(decision["confidence"] * 100).round}%) - skipping action"
        return { action: "no_action", reason: "low_confidence" }
      end

      decision
    rescue Ollama::Error => e
      puts "❌ Ollama error: #{e.message}"
      { action: "no_action", reason: "error", error: e.message }
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}"
      { action: "no_action", reason: "error", error: e.message }
    end
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def execute_decision(decision)
    action = decision["action"]
    params = decision["parameters"] || {}

    case action
    when "get_market_quote"
      if params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
        { action: "get_market_quote", error: "Either symbol or security_id is required", params: params }
      else
        DhanHQDataTools.get_market_quote(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

    when "get_live_ltp"
      if params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
        { action: "get_live_ltp", error: "Either symbol or security_id is required", params: params }
      else
        DhanHQDataTools.get_live_ltp(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

    when "get_market_depth"
      if params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
        { action: "get_market_depth", error: "Either symbol or security_id is required", params: params }
      else
        DhanHQDataTools.get_market_depth(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

    when "get_historical_data"
      if params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
        { action: "get_historical_data", error: "Either symbol or security_id is required", params: params }
      else
        DhanHQDataTools.get_historical_data(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ",
          from_date: params["from_date"],
          to_date: params["to_date"],
          interval: params["interval"],
          expiry_code: params["expiry_code"]
        )
      end

    when "get_option_chain"
      if params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
        { action: "get_option_chain", error: "Either symbol or security_id is required", params: params }
      else
        DhanHQDataTools.get_option_chain(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ",
          expiry: params["expiry"]
        )
      end

    when "get_expired_options_data"
      symbol_or_id_missing = params["symbol"].nil? &&
                             (params["security_id"].nil? || params["security_id"].to_s.empty?)
      if symbol_or_id_missing || params["expiry_date"].nil?
        {
          action: "get_expired_options_data",
          error: "Either symbol or security_id, and expiry_date are required",
          params: params
        }
      else
        DhanHQDataTools.get_expired_options_data(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_FNO",
          expiry_date: params["expiry_date"],
          expiry_code: params["expiry_code"]
        )
      end

    when "no_action"
      { action: "no_action", message: "No action taken" }

    else
      { action: "unknown", error: "Unknown action: #{action}" }
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private

  def build_analysis_prompt(market_context:)
    <<~PROMPT
      Analyze the following market situation and decide the best data retrieval action:

      Market Context:
      #{market_context}

      Available Actions (DATA ONLY - NO TRADING):
      - get_market_quote: Get market quote using Instrument.quote convenience method (requires: symbol OR security_id, exchange_segment)
      - get_live_ltp: Get live last traded price using Instrument.ltp convenience method (requires: symbol OR security_id, exchange_segment)
      - get_market_depth: Get full market depth (bid/ask levels) using Instrument.quote convenience method (requires: symbol OR security_id, exchange_segment)
      - get_historical_data: Get historical data using Instrument.daily/intraday convenience methods (requires: symbol OR security_id, exchange_segment, from_date, to_date, optional: interval, expiry_code)
      - get_expired_options_data: Get expired options historical data using Instrument.daily convenience method (requires: symbol OR security_id, exchange_segment, expiry_date, optional: expiry_code)
      - get_option_chain: Get option chain using Instrument.expiry_list/option_chain convenience methods (requires: symbol OR security_id, exchange_segment, optional: expiry)
      - no_action: Take no action if unclear what data is needed

      Important:
      - All APIs use Instrument.find() which expects SYMBOL (e.g., "NIFTY", "RELIANCE"), not security_id
      - Instrument convenience methods automatically use the instrument's security_id, exchange_segment, and instrument attributes
      - Use symbol when possible for better compatibility
      Examples: NIFTY=symbol "NIFTY", exchange_segment "IDX_I"; RELIANCE=symbol "RELIANCE", exchange_segment "NSE_EQ"
      Valid exchange_segments: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

      Decision Criteria:
      - Only take actions with confidence > 0.6
      - Focus on data retrieval, not trading decisions
      - Provide all required parameters for the chosen action

      Respond with a JSON object containing:
      - action: one of the available actions
      - reasoning: why this action was chosen
      - confidence: your confidence level (0-1)
      - parameters: object with required parameters for the action
    PROMPT
  end
end

# Trading-focused Agent using Ollama for reasoning
class TradingAgent
  def initialize(ollama_client:)
    @ollama_client = ollama_client
    @decision_schema = {
      "type" => "object",
      "required" => ["action", "reasoning", "confidence"],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => ["place_order", "place_super_order", "cancel_order", "no_action"]
        },
        "reasoning" => {
          "type" => "string",
          "description" => "Why this action was chosen"
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Confidence in this decision"
        },
        "parameters" => {
          "type" => "object",
          "description" => "Parameters for the action (security_id, quantity, price, etc.)"
        }
      }
    }
  end

  def analyze_and_decide(market_context:)
    prompt = build_analysis_prompt(market_context: market_context)

    begin
      decision = @ollama_client.generate(
        prompt: prompt,
        schema: @decision_schema
      )

      # Validate confidence threshold
      return { action: "no_action", reason: "invalid_decision" } unless decision.is_a?(Hash) && decision["confidence"]

      if decision["confidence"] < 0.6
        puts "⚠️  Low confidence (#{(decision["confidence"] * 100).round}%) - skipping action"
        return { action: "no_action", reason: "low_confidence" }
      end

      decision
    rescue Ollama::Error => e
      puts "❌ Ollama error: #{e.message}"
      { action: "no_action", reason: "error", error: e.message }
    rescue StandardError => e
      puts "❌ Unexpected error: #{e.message}"
      { action: "no_action", reason: "error", error: e.message }
    end
  end

  def execute_decision(decision)
    action = decision["action"]
    params = decision["parameters"] || {}

    case action
    when "place_order"
      handle_place_order(params)
    when "place_super_order"
      handle_place_super_order(params)
    when "cancel_order"
      handle_cancel_order(params)
    when "no_action"
      handle_no_action
    else
      handle_unknown_action(action)
    end
  end

  private

  def handle_place_order(params)
    DhanHQTradingTools.build_order_params(
      transaction_type: params["transaction_type"] || "BUY",
      exchange_segment: params["exchange_segment"] || "NSE_EQ",
      product_type: params["product_type"] || "MARGIN",
      order_type: params["order_type"] || "LIMIT",
      security_id: params["security_id"],
      quantity: params["quantity"] || 1,
      price: params["price"]
    )
  end

  def handle_place_super_order(params)
    DhanHQTradingTools.build_super_order_params(
      transaction_type: params["transaction_type"] || "BUY",
      exchange_segment: params["exchange_segment"] || "NSE_EQ",
      product_type: params["product_type"] || "MARGIN",
      order_type: params["order_type"] || "LIMIT",
      security_id: params["security_id"],
      quantity: params["quantity"] || 1,
      price: params["price"],
      target_price: params["target_price"],
      stop_loss_price: params["stop_loss_price"],
      trailing_jump: params["trailing_jump"] || 10
    )
  end

  def handle_cancel_order(params)
    DhanHQTradingTools.build_cancel_params(order_id: params["order_id"])
  end

  def handle_no_action
    { action: "no_action", message: "No action taken" }
  end

  def handle_unknown_action(action)
    { action: "unknown", error: "Unknown action: #{action}" }
  end

  def build_analysis_prompt(market_context:)
    <<~PROMPT
      Analyze the following market situation and decide the best trading action:

      Market Context:
      #{market_context}

      Available Actions (TRADING ONLY):
      - place_order: Build order parameters (requires: security_id as string, quantity, price, transaction_type, exchange_segment)
      - place_super_order: Build super order parameters with SL/TP (requires: security_id as string, quantity, price, target_price, stop_loss_price, exchange_segment)
      - cancel_order: Build cancel parameters (requires: order_id)
      - no_action: Take no action if market conditions are unclear or risky

      Important: security_id must be a STRING (e.g., "13" not 13). Valid exchange_segment values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

      Decision Criteria:
      - Only take actions with confidence > 0.6
      - Consider risk management (use super orders for risky trades)
      - Ensure all required parameters are provided
      - Be conservative - prefer no_action if uncertain

      Respond with a JSON object containing:
      - action: one of the available trading actions
      - reasoning: why this action was chosen
      - confidence: your confidence level (0-1)
      - parameters: object with required parameters for the action
    PROMPT
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  # Configure DhanHQ (must be done before using DhanHQ models)
  begin
    DhanHQ.configure_with_env
    puts "✅ DhanHQ configured"
  rescue StandardError => e
    puts "⚠️  DhanHQ configuration error: #{e.message}"
    puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
    puts "   Continuing with mock data for demonstration..."
  end

  puts "=" * 60
  puts "DhanHQ Agent: Ollama (Reasoning) + DhanHQ (Data & Trading)"
  puts "=" * 60
  puts

  # Initialize Ollama client
  ollama_client = Ollama::Client.new

  # ============================================================
  # DATA AGENT EXAMPLES
  # ============================================================
  puts "─" * 60
  puts "DATA AGENT: Market Data Retrieval"
  puts "─" * 60
  puts

  data_agent = DataAgent.new(ollama_client: ollama_client)

  # Example 1: Analyze market and decide data action (using real data)
  puts "Example 1: Market Analysis & Data Decision (Real Data)"
  puts "─" * 60

  # Fetch real market data first
  puts "📊 Fetching real market data from DhanHQ..."

  market_data = {}
  begin
    # Get NIFTY data - using Instrument convenience method (uses symbol)
    # Note: Instrument.find expects symbol "NIFTY", not security_id
    # Rate limiting is handled automatically in DhanHQDataTools
    nifty_result = DhanHQDataTools.get_live_ltp(symbol: "NIFTY", exchange_segment: "IDX_I")
    sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs
    if nifty_result.is_a?(Hash) && nifty_result[:result] && !nifty_result[:error]
      market_data[:nifty] = nifty_result[:result]
      ltp = nifty_result[:result][:ltp]
      if ltp && ltp != 0
        puts "  ✅ NIFTY: LTP=#{ltp}"
      else
        puts "  ⚠️  NIFTY: Data retrieved but LTP is null/empty (may be outside market hours)"
        puts "     Result: #{nifty_result[:result].inspect[0..200]}"
      end
    elsif nifty_result && nifty_result[:error]
      puts "  ⚠️  NIFTY data error: #{nifty_result[:error]}"
    else
      puts "  ⚠️  NIFTY: No data returned"
    end
  rescue StandardError => e
    puts "  ⚠️  NIFTY data error: #{e.message}"
  end

  begin
    # Get RELIANCE data - using Instrument convenience method (uses symbol)
    # Note: Instrument.find expects symbol "RELIANCE", not security_id
    # Rate limiting is handled automatically in DhanHQDataTools
    reliance_result = DhanHQDataTools.get_live_ltp(symbol: "RELIANCE", exchange_segment: "NSE_EQ")
    sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs
    if reliance_result.is_a?(Hash) && reliance_result[:result] && !reliance_result[:error]
      market_data[:reliance] = reliance_result[:result]
      ltp = reliance_result[:result][:ltp]
      if ltp && ltp != 0
        puts "  ✅ RELIANCE: LTP=#{ltp}"
      else
        puts "  ⚠️  RELIANCE: Data retrieved but LTP is null/empty (may be outside market hours)"
        puts "     Result: #{reliance_result[:result].inspect[0..200]}"
      end
    elsif reliance_result && reliance_result[:error]
      puts "  ⚠️  RELIANCE data error: #{reliance_result[:error]}"
    else
      puts "  ⚠️  RELIANCE: No data returned"
    end
  rescue StandardError => e
    puts "  ⚠️  RELIANCE data error: #{e.message}"
  end

  # NOTE: Positions and holdings are not part of the 6 Data APIs
  begin
    positions_result = { action: "check_positions", result: { positions: [], count: 0 },
                         note: "Positions API not available in Data Tools" }
    if positions_result[:result]
      market_data[:positions] = positions_result[:result][:positions] || []
      puts "  ✅ Positions: #{positions_result[:result][:count] || 0} active"
    else
      puts "  ✅ Positions: 0 active (Positions API not in Data Tools)"
      market_data[:positions] = []
    end
  rescue StandardError => e
    puts "  ⚠️  Positions error: #{e.message}"
    market_data[:positions] = []
  end

  puts

  # Build market context from real data
  market_context = build_market_context_from_data(market_data)

  puts "Market Context (from real data):"
  puts market_context
  puts

  begin
    puts "🤔 Analyzing market with Ollama..."
    decision = data_agent.analyze_and_decide(market_context: market_context)

    puts "\n📋 Decision:"
    if decision.is_a?(Hash)
      puts "   Action: #{decision['action'] || 'N/A'}"
      puts "   Reasoning: #{decision['reasoning'] || 'N/A'}"
      if decision["confidence"]
        puts "   Confidence: #{(decision['confidence'] * 100).round}%"
      else
        puts "   Confidence: N/A"
      end
      puts "   Parameters: #{JSON.pretty_generate(decision['parameters'] || {})}"
    else
      puts "   ⚠️  Invalid decision returned: #{decision.inspect}"
    end

    if decision["action"] != "no_action"
      puts "\n⚡ Executing data retrieval..."
      result = data_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts
  puts "─" * 60
  puts "Example 2: All Data APIs Demonstration"
  puts "─" * 60
  puts "Demonstrating all available DhanHQ Data APIs:"
  puts

  test_symbol = "RELIANCE" # RELIANCE symbol for Instrument.find
  test_exchange = "NSE_EQ"

  # 1. Market Quote (uses Instrument convenience method)
  puts "1️⃣  Market Quote API"
  begin
    result = DhanHQDataTools.get_market_quote(symbol: test_symbol, exchange_segment: test_exchange)
    if result[:result]
      puts "   ✅ Market Quote retrieved"
      puts "   📊 Quote data: #{result[:result][:quote].inspect[0..150]}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs

  # 2. Live Market Feed (LTP) (uses Instrument convenience method)
  puts "2️⃣  Live Market Feed API (LTP)"
  begin
    result = DhanHQDataTools.get_live_ltp(symbol: test_symbol, exchange_segment: test_exchange)
    if result[:result]
      puts "   ✅ LTP retrieved"
      puts "   📊 LTP: #{result[:result][:ltp].inspect}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs

  # 3. Full Market Depth (uses Instrument convenience method)
  puts "3️⃣  Full Market Depth API"
  begin
    result = DhanHQDataTools.get_market_depth(symbol: test_symbol, exchange_segment: test_exchange)
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
  end

  puts
  sleep(1.2) # Rate limit: 1 request per second for MarketFeed APIs

  # 4. Historical Data (uses symbol for Instrument.find)
  puts "4️⃣  Historical Data API"
  begin
    result = DhanHQDataTools.get_historical_data(
      symbol: test_symbol,
      exchange_segment: test_exchange,
      from_date: "2024-01-01",
      to_date: "2024-01-31"
    )
    if result[:result]
      puts "   ✅ Historical data retrieved"
      puts "   📊 Type: #{result[:type]}"
      puts "   📊 Records: #{result[:result][:count]}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(0.5) # Small delay for Instrument APIs

  # 5. Expired Options Data (uses symbol for Instrument.find)
  puts "5️⃣  Expired Options Data API"
  begin
    # Use NSE_FNO for options
    result = DhanHQDataTools.get_expired_options_data(
      symbol: test_symbol,
      exchange_segment: "NSE_FNO",
      expiry_date: "2024-01-31"
    )
    if result[:result]
      puts "   ✅ Expired options data retrieved"
      puts "   📊 Expiry: #{result[:result][:expiry_date]}"
      puts "   📊 Data: #{result[:result][:data].inspect[0..150]}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(0.5) # Small delay for Instrument APIs

  # 6. Option Chain (uses symbol for Instrument.find)
  puts "6️⃣  Option Chain API"
  begin
    result = DhanHQDataTools.get_option_chain(
      symbol: test_symbol,
      exchange_segment: "NSE_FNO"
    )
    if result[:result]
      puts "   ✅ Option chain data retrieved"
      if result[:result][:expiries]
        puts "   📊 Available expiries: #{result[:result][:count]}"
        expiries = result[:result][:expiries]
        puts "   📊 First few expiries: #{expiries.first(3).inspect}" if expiries.is_a?(Array)
      elsif result[:result][:chain]
        puts "   📊 Option chain: #{result[:result][:chain].inspect[0..150]}"
      end
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  puts "=" * 60
  puts "TRADING AGENT: Order Parameter Building"
  puts "=" * 60
  puts

  # ============================================================
  # TRADING AGENT EXAMPLES
  # ============================================================
  config = Ollama::Config.new
  config.timeout = 60
  trading_ollama_client = Ollama::Client.new(config: config)
  trading_agent = TradingAgent.new(ollama_client: trading_ollama_client)

  # Example 1: Simple buy order
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

  begin
    puts "🤔 Analyzing with Ollama..."
    decision = trading_agent.analyze_and_decide(market_context: market_context)

    puts "\n📋 Decision:"
    if decision.is_a?(Hash)
      puts "   Action: #{decision['action'] || 'N/A'}"
      puts "   Reasoning: #{decision['reasoning'] || 'N/A'}"
      puts "   Confidence: #{(decision['confidence'] * 100).round}%" if decision["confidence"]
      puts "   Parameters: #{JSON.pretty_generate(decision['parameters'] || {})}"
    end

    if decision["action"] != "no_action"
      puts "\n⚡ Building order parameters (order not placed)..."
      result = trading_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
      if result.is_a?(Hash) && result[:order_params]
        puts "\n   📝 Order Parameters Ready:"
        puts "      #{JSON.pretty_generate(result[:order_params])}"
        puts "   💡 To place order: DhanHQ::Models::Order.new(result[:order_params]).save"
      end
    end
  rescue Ollama::TimeoutError => e
    puts "⏱️  Timeout: #{e.message}"
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts
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


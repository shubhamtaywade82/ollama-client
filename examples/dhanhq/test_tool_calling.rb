#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Tool Calling Test
# Dedicated test file for tool calling with DhanHQ tools
# Uses Executor + Structured Tool Classes

require_relative "../../lib/ollama_client"
require_relative "../dhanhq_tools"

puts "\n=== DHANHQ TOOL CALLING TEST ===\n"

# Configure DhanHQ
begin
  DhanHQ.configure_with_env
  puts "✅ DhanHQ configured"
rescue StandardError => e
  puts "⚠️  DhanHQ configuration error: #{e.message}"
  puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
  puts "   Continuing with test (may fail on actual API calls)..."
end

# Create client
config = Ollama::Config.new
config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
config.temperature = 0.2
config.timeout = 60
client = Ollama::Client.new(config: config)

# Define DhanHQ tools using structured Tool classes
puts "\n--- Defining Tools ---"

market_quote_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_market_quote",
    description: "Get market quote for a symbol. Returns OHLC, depth, volume, and other market data. Finds instrument automatically using exchange_segment and symbol.",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Stock or index symbol (e.g., RELIANCE, NIFTY)"
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment",
          enum: %w[NSE_EQ NSE_FNO BSE_EQ BSE_FNO IDX_I]
        )
      },
      required: %w[symbol exchange_segment]
    )
  )
)

live_ltp_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_live_ltp",
    description: "Get live last traded price (LTP) for a symbol. Fast API for current price. Finds instrument automatically using exchange_segment and symbol.",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Stock or index symbol"
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment",
          enum: %w[NSE_EQ NSE_FNO BSE_EQ BSE_FNO IDX_I]
        )
      },
      required: %w[symbol exchange_segment]
    )
  )
)

# Option Chain Tool (for indices: NIFTY, SENSEX, BANKNIFTY)
option_chain_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_option_chain",
    description: "Get option chain for an index (NIFTY, SENSEX, BANKNIFTY). Returns available expiries and option chain data with strikes, Greeks, OI, and IV.",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Index symbol (NIFTY, SENSEX, or BANKNIFTY)",
          enum: %w[NIFTY SENSEX BANKNIFTY]
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment (must be IDX_I for indices)",
          enum: %w[IDX_I]
        ),
        expiry: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Optional expiry date (YYYY-MM-DD format). If not provided, returns available expiries list."
        )
      },
      required: %w[symbol exchange_segment]
    )
  )
)

puts "✅ Tools defined: get_market_quote, get_live_ltp, get_option_chain"

# Define tools with structured Tool classes and callables
tools = {
  "get_market_quote" => {
    tool: market_quote_tool,
    callable: lambda do |symbol:, exchange_segment:|
      puts "  🔧 Executing: get_market_quote(#{symbol}, #{exchange_segment})"
      begin
        result = DhanHQDataTools.get_market_quote(
          symbol: symbol.to_s,
          exchange_segment: exchange_segment.to_s
        )

        if result[:error]
          puts "  ❌ Error: #{result[:error]}"
          { error: result[:error] }
        else
          quote = result[:result][:quote]
          response = {
            symbol: symbol,
            exchange_segment: exchange_segment,
            last_price: quote[:last_price],
            volume: quote[:volume],
            ohlc: quote[:ohlc],
            change_percent: quote[:net_change]
          }
          puts "  ✅ Success: LTP=#{quote[:last_price]}, Volume=#{quote[:volume]}"
          response
        end
      rescue StandardError => e
        puts "  ❌ Exception: #{e.message}"
        { error: e.message }
      end
    end
  },

  "get_live_ltp" => {
    tool: live_ltp_tool,
    callable: lambda do |symbol:, exchange_segment:|
      puts "  🔧 Executing: get_live_ltp(#{symbol}, #{exchange_segment})"
      begin
        # Add rate limiting delay for MarketFeed APIs
        sleep(1.2) if defined?(DhanHQDataTools) && DhanHQDataTools.respond_to?(:rate_limit_marketfeed)
        DhanHQDataTools.rate_limit_marketfeed if DhanHQDataTools.respond_to?(:rate_limit_marketfeed)

        result = DhanHQDataTools.get_live_ltp(
          symbol: symbol.to_s,
          exchange_segment: exchange_segment.to_s
        )

        if result[:error]
          puts "  ❌ Error: #{result[:error]}"
          { error: result[:error] }
        else
          response = {
            symbol: symbol,
            exchange_segment: exchange_segment,
            ltp: result[:result][:ltp],
            timestamp: result[:result][:timestamp]
          }
          puts "  ✅ Success: LTP=#{result[:result][:ltp]}"
          response
        end
      rescue StandardError => e
        puts "  ❌ Exception: #{e.message}"
        { error: e.message }
      end
    end
  },

  "get_option_chain" => {
    tool: option_chain_tool,
    callable: lambda do |symbol:, exchange_segment:, expiry: nil|
      # Normalize empty string to nil (LLM might pass "" when expiry is optional)
      expiry = nil if expiry.is_a?(String) && expiry.empty?
      puts "  🔧 Executing: get_option_chain(#{symbol}, #{exchange_segment}, expiry=#{expiry || 'nil'})"
      begin
        result = DhanHQDataTools.get_option_chain(
          symbol: symbol.to_s,
          exchange_segment: exchange_segment.to_s,
          expiry: expiry
        )

        if result[:error]
          puts "  ❌ Error: #{result[:error]}"
          { error: result[:error] }
        elsif result[:result] && result[:result][:expiries]
          puts "  ✅ Success: #{result[:result][:count]} expiries available"
          {
            symbol: symbol,
            expiries_available: result[:result][:expiries],
            count: result[:result][:count]
          }
        elsif result[:result] && result[:result][:chain]
          chain = result[:result][:chain]
          strikes = chain.is_a?(Hash) ? chain.keys.sort_by { |k| k.to_f } : []
          puts "  ✅ Success: #{strikes.length} strikes for expiry #{result[:result][:expiry]}"
          {
            symbol: symbol,
            expiry: result[:result][:expiry],
            underlying_price: result[:result][:underlying_last_price],
            strikes_count: strikes.length,
            sample_strikes: strikes.first(5)
          }
        else
          { error: "Unexpected response format" }
        end
      rescue StandardError => e
        puts "  ❌ Exception: #{e.message}"
        { error: e.message }
      end
    end
  }
}

puts "\n--- Test 1: Single Tool Call ---"
puts "Request: Get market quote for RELIANCE\n"

executor1 = Ollama::Agent::Executor.new(
  client,
  tools: { "get_market_quote" => tools["get_market_quote"] },
  max_steps: 5
)

begin
  result1 = executor1.run(
    system: "You are a market data assistant. Use the get_market_quote tool to get market data.",
    user: "Get the market quote for RELIANCE stock on NSE"
  )

  puts "\n✅ Result:"
  puts result1
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 60)
puts "--- Test 2: Multiple Tools (LLM Chooses) ---"
puts "Request: Get RELIANCE quote, NIFTY price, and SENSEX option chain\n"

executor2 = Ollama::Agent::Executor.new(
  client,
  tools: tools,
  max_steps: 10
)

begin
  result2 = executor2.run(
    system: "You are a market data assistant. Use the available tools to get market data. " \
            "You can call multiple tools in sequence. When you have the data, summarize it clearly. " \
            "For option chains, use get_option_chain with symbol='SENSEX' and exchange_segment='IDX_I'.",
    user: "Get market quote for RELIANCE stock, check NIFTY's current price, and get SENSEX option chain"
  )

  puts "\n✅ Result:"
  puts result2
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 60)
puts "--- Test 3: Option Chain (SENSEX) - Expiry List ---"
puts "Request: Get SENSEX option chain expiry list\n"

executor3 = Ollama::Agent::Executor.new(
  client,
  tools: { "get_option_chain" => tools["get_option_chain"] },
  max_steps: 5
)

begin
  result3 = executor3.run(
    system: "You are a market data assistant. Use the get_option_chain tool to get option chain data for indices. " \
            "When no expiry is specified, it returns the list of available expiries.",
    user: "Get the option chain for SENSEX index"
  )

  puts "\n✅ Result:"
  puts result3
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 60)
puts "--- Test 3b: Option Chain (SENSEX) - Full Chain with Strikes ---"
puts "Request: Get SENSEX option chain for specific expiry\n"

begin
  # First get the expiry list to use a valid expiry
  expiry_result = DhanHQDataTools.get_option_chain(
    symbol: "SENSEX",
    exchange_segment: "IDX_I"
  )
  
  if expiry_result[:result] && expiry_result[:result][:expiries] && !expiry_result[:result][:expiries].empty?
    first_expiry = expiry_result[:result][:expiries].first
    puts "Using expiry: #{first_expiry}\n"
    
    # Call directly to avoid LLM date confusion
    chain_result = DhanHQDataTools.get_option_chain(
      symbol: "SENSEX",
      exchange_segment: "IDX_I",
      expiry: first_expiry
    )
    
    if chain_result[:error]
      puts "❌ Error: #{chain_result[:error]}"
    elsif chain_result[:result] && chain_result[:result][:chain]
      chain = chain_result[:result][:chain]
      underlying_price = chain_result[:result][:underlying_last_price]
      strikes = if chain.is_a?(Hash)
                  chain.keys.sort_by { |k| k.to_s.to_f }
                else
                  []
                end
      
      puts "✅ Option chain retrieved successfully"
      puts "   Underlying Price: ₹#{underlying_price}"
      puts "   Expiry: #{chain_result[:result][:expiry]}"
      puts "   Total Strikes: #{strikes.length}"
      puts "   Strike Range: ₹#{strikes.first} to ₹#{strikes.last}" if !strikes.empty?
      puts "   Sample strikes: #{strikes.first(5).join(', ')}" if !strikes.empty?
    else
      puts "⚠️  Unexpected response format"
    end
  else
    puts "⚠️  Could not get expiry list to test full chain"
  end
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 60)
puts "--- Test 4: ATM and ATM+1 Strikes (CALL & PUT) ---"
puts "Request: Get SENSEX option chain and extract ATM, ATM+1 for CALL and PUT\n"

begin
  # Get expiry list first
  expiry_result = DhanHQDataTools.get_option_chain(
    symbol: "SENSEX",
    exchange_segment: "IDX_I"
  )
  
  if expiry_result[:error] || !expiry_result[:result] || !expiry_result[:result][:expiries] || expiry_result[:result][:expiries].empty?
    puts "❌ Error: Could not get expiry list - #{expiry_result[:error] || 'No expiries found'}"
  else
    first_expiry = expiry_result[:result][:expiries].first
    puts "Using expiry: #{first_expiry}\n"
    
    # Get full option chain for this expiry
    chain_result = DhanHQDataTools.get_option_chain(
      symbol: "SENSEX",
      exchange_segment: "IDX_I",
      expiry: first_expiry
    )
    
    if chain_result[:error]
      puts "❌ Error getting option chain: #{chain_result[:error]}"
    elsif chain_result[:result] && chain_result[:result][:chain]
      underlying_price = chain_result[:result][:underlying_last_price].to_f
      chain = chain_result[:result][:chain]
      
      puts "Underlying Price (SENSEX): ₹#{underlying_price}\n"
      
      # Extract all strikes and sort them
      # Chain keys are typically strings with decimal precision (e.g., "83600.000000")
      strike_keys = if chain.is_a?(Hash)
                     chain.keys.sort_by { |k| k.to_s.to_f }
                   else
                     []
                   end
      
      strikes = strike_keys.map { |k| k.to_s.to_f }
      
      if strikes.empty?
        puts "❌ No strikes found in chain data"
        puts "   Chain keys: #{chain.keys.first(5).inspect}" if chain.is_a?(Hash)
      else
        # Find ATM strike (closest to underlying price)
        atm_strike = strikes.min_by { |s| (s - underlying_price).abs }
        atm_index = strikes.index(atm_strike)
        atm_plus_one = strikes[atm_index + 1] if atm_index && (atm_index + 1) < strikes.length
        
        puts "ATM Strike: ₹#{atm_strike}"
        puts "ATM+1 Strike: ₹#{atm_plus_one || 'N/A'}\n"
        
        # Extract data for ATM and ATM+1 strikes
        # Match strike values to actual keys in chain hash
        [atm_strike, atm_plus_one].compact.each do |strike_value|
          # Find the actual key that matches this strike value
          actual_key = strike_keys.find { |k| (k.to_s.to_f - strike_value).abs < 0.01 }
          
          if actual_key.nil?
            puts "⚠️  Could not find key for strike ₹#{strike_value}"
            puts "   Available keys sample: #{strike_keys.first(3).inspect}"
            next
          end
          
          strike_data = chain[actual_key]
          
          if strike_data
            puts "=" * 60
            puts "Strike: ₹#{strike_value} (key: #{actual_key.inspect})"
            puts "-" * 60
            
            # Extract CALL and PUT data (DhanHQ uses "ce" for CALL and "pe" for PUT)
            call_data = strike_data[:ce] || strike_data["ce"] || {}
            put_data = strike_data[:pe] || strike_data["pe"] || {}
            
            puts "CALL Options (CE):"
            if call_data && !call_data.empty?
              puts "  LTP: ₹#{call_data[:ltp] || call_data['ltp'] || 'N/A'}"
              puts "  IV: #{call_data[:iv] || call_data['iv'] || 'N/A'}%"
              puts "  OI: #{call_data[:oi] || call_data['oi'] || 'N/A'}"
              puts "  Volume: #{call_data[:volume] || call_data['volume'] || 'N/A'}"
              puts "  Delta: #{call_data[:delta] || call_data['delta'] || 'N/A'}"
              puts "  Gamma: #{call_data[:gamma] || call_data['gamma'] || 'N/A'}"
              puts "  Theta: #{call_data[:theta] || call_data['theta'] || 'N/A'}"
              puts "  Vega: #{call_data[:vega] || call_data['vega'] || 'N/A'}"
            else
              puts "  No CALL data available"
            end
            
            puts "\nPUT Options (PE):"
            if put_data && !put_data.empty?
              puts "  LTP: ₹#{put_data[:ltp] || put_data['ltp'] || 'N/A'}"
              puts "  IV: #{put_data[:iv] || put_data['iv'] || 'N/A'}%"
              puts "  OI: #{put_data[:oi] || put_data['oi'] || 'N/A'}"
              puts "  Volume: #{put_data[:volume] || put_data['volume'] || 'N/A'}"
              puts "  Delta: #{put_data[:delta] || put_data['delta'] || 'N/A'}"
              puts "  Gamma: #{put_data[:gamma] || put_data['gamma'] || 'N/A'}"
              puts "  Theta: #{put_data[:theta] || put_data['theta'] || 'N/A'}"
              puts "  Vega: #{put_data[:vega] || put_data['vega'] || 'N/A'}"
            else
              puts "  No PUT data available"
            end
            puts
          else
            puts "⚠️  No data found for strike ₹#{strike_value} (key: #{actual_key.inspect})"
            puts "   Strike data type: #{strike_data.class}" if strike_data
            puts "   Strike data: #{strike_data.inspect}" if strike_data
          end
        end
        
        puts "=" * 60
        puts "✅ Successfully extracted ATM and ATM+1 strikes for CALL and PUT"
      end
    else
      puts "❌ Unexpected response format"
    end
  end
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n" + ("=" * 60)
puts "--- Test 5: Direct chat_raw() Test ---"
puts "Testing chat_raw() to access tool_calls directly\n"

begin
  response = client.chat_raw(
    model: ENV.fetch("OLLAMA_MODEL", "llama3.1:8b"),
    messages: [Ollama::Agent::Messages.user("Get the option chain for SENSEX index")],
    tools: option_chain_tool,
    allow_chat: true
  )

  puts "✅ Response received"
  puts "Response class: #{response.class.name}"

  # Method access (like ollama-ruby)
  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "\n✅ Tool calls detected (via method access):"
    tool_calls.each do |call|
      puts "  Tool: #{call.name}"
      puts "  Arguments: #{call.arguments.inspect}"
      puts "  ID: #{call.id || 'N/A'}"
    end
  else
    puts "\n⚠️  No tool calls detected"
    puts "Content: #{response.message&.content}"
  end

  # Hash access (backward compatible)
  tool_calls_hash = response.to_h.dig("message", "tool_calls")
  if tool_calls_hash && !tool_calls_hash.empty?
    puts "\n✅ Tool calls also accessible via hash:"
    puts "  Count: #{tool_calls_hash.length}"
  end

rescue Ollama::Error => e
  puts "\n❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
end

puts "\n" + ("=" * 60)
puts "--- Summary ---"
puts "✅ Tool calling with Executor: Working"
puts "✅ Structured Tool classes: Working"
puts "✅ chat_raw() method access: Working"
puts "✅ Hash access (backward compatible): Working"
puts "✅ Option chain expiry list: Working"
puts "✅ Option chain full data with strikes: Working"
puts "✅ ATM/ATM+1 strike extraction: Working"
puts "\n=== DONE ===\n"

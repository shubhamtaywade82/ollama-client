#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Tool Calling Test - Verbose Version
# Shows the complete tool calling flow: LLM decides → Executor executes

require_relative "../../lib/ollama_client"
require_relative "../dhanhq_tools"

puts "\n=== DHANHQ TOOL CALLING TEST (VERBOSE) ===\n"
puts "This demonstrates REAL tool calling:\n"
puts "  1. LLM receives user query + tool definitions"
puts "  2. LLM DECIDES which tools to call (not your code!)"
puts "  3. LLM returns tool_calls in response"
puts "  4. Executor detects tool_calls and executes callables"
puts "  5. Tool results fed back to LLM"
puts "  6. LLM generates final answer\n"

# Configure DhanHQ
begin
  DhanHQ.configure_with_env
  puts "✅ DhanHQ configured\n"
rescue StandardError => e
  puts "⚠️  DhanHQ configuration error: #{e.message}\n"
end

# Create client
config = Ollama::Config.new
config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
config.temperature = 0.2
config.timeout = 60
client = Ollama::Client.new(config: config)

# Define tools
market_quote_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_market_quote",
    description: "Get market quote for a symbol",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Stock symbol"
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment",
          enum: %w[NSE_EQ BSE_EQ IDX_I]
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
    description: "Get live last traded price",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Stock symbol"
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment",
          enum: %w[NSE_EQ BSE_EQ IDX_I]
        )
      },
      required: %w[symbol exchange_segment]
    )
  )
)

option_chain_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_option_chain",
    description: "Get option chain for an index (NIFTY, SENSEX, BANKNIFTY). " \
                 "Returns available expiries and option chain data with strikes, Greeks, OI, and IV.",
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

# Define callables (these are just implementations - LLM decides when to call them)
tools = {
  "get_option_chain" => {
    tool: option_chain_tool,
    callable: lambda do |symbol:, exchange_segment:, expiry: nil|
      # Normalize empty string to nil (LLM might pass "" when expiry is optional)
      expiry = nil if expiry.is_a?(String) && expiry.empty?
      puts "\n  [TOOL EXECUTION] get_option_chain called by Executor"
      puts "    Args: symbol=#{symbol}, exchange_segment=#{exchange_segment}, expiry=#{expiry || 'nil'}"
      puts "    Note: This is called AFTER LLM decided to use this tool!"
      result = DhanHQDataTools.get_option_chain(
        symbol: symbol.to_s,
        exchange_segment: exchange_segment.to_s,
        expiry: expiry
      )
      if result[:error]
        { error: result[:error] }
      elsif result[:result] && result[:result][:expiries]
        # Return expiry list
        {
          symbol: symbol,
          expiries_available: result[:result][:expiries],
          count: result[:result][:count]
        }
      elsif result[:result] && result[:result][:chain]
        # Return option chain data
        chain = result[:result][:chain]
        strikes = chain.is_a?(Hash) ? chain.keys.sort_by(&:to_f) : []
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
      { error: e.message }
    end
  },

  "get_market_quote" => {
    tool: market_quote_tool,
    callable: lambda do |symbol:, exchange_segment:|
      puts "\n  [TOOL EXECUTION] get_market_quote called by Executor"
      puts "    Args: symbol=#{symbol}, exchange_segment=#{exchange_segment}"
      puts "    Note: This is called AFTER LLM decided to use this tool!"
      result = DhanHQDataTools.get_market_quote(
        symbol: symbol.to_s,
        exchange_segment: exchange_segment.to_s
      )
      if result[:error]
        { error: result[:error] }
      else
        quote = result[:result][:quote]
        {
          symbol: symbol,
          last_price: quote[:last_price],
          volume: quote[:volume],
          ohlc: quote[:ohlc]
        }
      end
    end
  },

  "get_live_ltp" => {
    tool: live_ltp_tool,
    callable: lambda do |symbol:, exchange_segment:|
      puts "\n  [TOOL EXECUTION] get_live_ltp called by Executor"
      puts "    Args: symbol=#{symbol}, exchange_segment=#{exchange_segment}"
      puts "    Note: This is called AFTER LLM decided to use this tool!"
      sleep(1.2) # Rate limiting
      result = DhanHQDataTools.get_live_ltp(
        symbol: symbol.to_s,
        exchange_segment: exchange_segment.to_s
      )
      if result[:error]
        { error: result[:error] }
      else
        {
          symbol: symbol,
          ltp: result[:result][:ltp]
        }
      end
    end
  }
}

puts "--- Step 1: Show what tools are available to LLM ---"
puts "Tools defined:"
puts "  - get_market_quote: Get market quote"
puts "  - get_live_ltp: Get live price"
puts "  - get_option_chain: Get option chain for indices (NIFTY, SENSEX, BANKNIFTY)"
puts "\nThese tool DEFINITIONS are sent to LLM (not executed yet)\n"

puts "--- Step 2: LLM receives query and DECIDES which tools to call ---"
puts "User query: 'Get RELIANCE quote, NIFTY price, and SENSEX option chain'\n"
puts "LLM will analyze this and decide to call:"
puts "  1. get_market_quote(RELIANCE, NSE_EQ)"
puts "  2. get_live_ltp(NIFTY, IDX_I)"
puts "  3. get_option_chain(SENSEX, IDX_I)"
puts "\nThis decision is made by the LLM, not by your code!\n"

puts "--- Step 3: Executor sends request to LLM with tool definitions ---"
puts "Sending to LLM via chat_raw() with tools parameter...\n"

# Create executor
executor = Ollama::Agent::Executor.new(
  client,
  tools: tools,
  max_steps: 10
)

begin
  result = executor.run(
    system: "You are a market data assistant. Use the available tools to get market data. " \
            "For option chains, you can get SENSEX options using get_option_chain with " \
            "symbol='SENSEX' and exchange_segment='IDX_I'.",
    user: "Get market quote for RELIANCE stock, check NIFTY's current price, and get SENSEX option chain"
  )

  puts "\n--- Step 4: Final result from LLM (after tool execution) ---"
  puts "=" * 60
  puts result
  puts "=" * 60
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.message}"
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
end

puts "\n--- Summary ---"
puts "✅ This IS real tool calling:"
puts "   - LLM decides which tools to call (not your code)"
puts "   - LLM returns tool_calls in response"
puts "   - Executor detects tool_calls and executes callables"
puts "   - Tool results fed back to LLM automatically"
puts "   - LLM generates final answer based on tool results"
puts "\nThe callables are just implementations - the LLM decides WHEN to call them!"
puts "\n=== DONE ===\n"

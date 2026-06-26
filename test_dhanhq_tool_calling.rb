#!/usr/bin/env ruby
# frozen_string_literal: true

# Test DhanHQ Tool Calling with chat_raw()
# Demonstrates using structured Tool classes with DhanHQ tools

require_relative "lib/ollama_client"
require_relative "examples/dhanhq_tools"

puts "\n=== DHANHQ TOOL CALLING TEST ===\n"
puts "Using chat_raw() to access tool_calls\n"

client = Ollama::Client.new

# Define DhanHQ tools using structured Tool classes
# This provides better type safety and LLM understanding

# Market Quote Tool
market_quote_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_market_quote",
    description: "Get market quote for a symbol. Returns OHLC, depth, volume, and other market data.",
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

# Live LTP Tool
live_ltp_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_live_ltp",
    description: "Get live last traded price (LTP) for a symbol. Fast API for current price.",
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

# Historical Data Tool
historical_data_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_historical_data",
    description: "Get historical price data (OHLCV) for a symbol. Supports daily, weekly, monthly intervals.",
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
        ),
        interval: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Data interval",
          enum: %w[daily weekly monthly]
        ),
        from_date: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Start date (YYYY-MM-DD format)"
        ),
        to_date: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "End date (YYYY-MM-DD format)"
        )
      },
      required: %w[symbol exchange_segment]
    )
  )
)

# Combine tools
dhanhq_tools = [market_quote_tool, live_ltp_tool, historical_data_tool]

puts "--- Test 1: Single tool (Market Quote) ---"
puts "Request: Get market quote for RELIANCE\n"

begin
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("Get the market quote for RELIANCE stock")],
    tools: market_quote_tool,
    allow_chat: true
  )

  puts "✅ Response received"
  puts "Response class: #{response.class.name}\n"

  # Method access (recommended - like ollama-ruby)
  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "✅ Tool calls detected (via method access):"
    tool_calls.each do |call|
      puts "  Tool: #{call.name}"
      puts "  Arguments: #{call.arguments.inspect}"
      puts "  ID: #{call.id}\n"
    end
  else
    puts "⚠️  No tool calls detected"
    puts "Content: #{response.message&.content}\n"
  end
rescue Ollama::Error => e
  puts "❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
  puts "\n   Note: Expected if Ollama server is not running"
  puts "   The important part is that tool_calls structure is correct"
end

puts "\n--- Test 2: Multiple tools (LLM chooses) ---"
puts "Request: Get current price for NIFTY\n"

begin
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("What's the current price of NIFTY?")],
    tools: dhanhq_tools, # Array of Tool objects
    allow_chat: true
  )

  puts "✅ Response received\n"

  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "✅ Tool calls detected:"
    tool_calls.each do |call|
      puts "  - #{call.name}"
      puts "    Args: #{call.arguments.inspect}\n"
    end
  else
    puts "⚠️  No tool calls detected"
    puts "Content: #{response.message&.content}\n"
  end
rescue Ollama::Error => e
  puts "❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
end

puts "\n--- Test 3: Compare chat() vs chat_raw() ---"
puts "Request: Get RELIANCE market data\n"

# chat_raw() - returns full response with tool_calls
puts "\nUsing chat_raw() (recommended for tool calling):"
begin
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("Get market data for RELIANCE")],
    tools: market_quote_tool,
    allow_chat: true
  )

  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "  ✅ Can access tool_calls: #{tool_calls.length} call(s)"
  else
    puts "  ⚠️  No tool_calls (content only)"
  end
rescue Ollama::Error => e
  puts "  ❌ Error: #{e.message}"
end

# chat() - returns content only
puts "\nUsing chat() (not recommended for tool calling):"
begin
  content = client.chat(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("Get market data for RELIANCE")],
    tools: market_quote_tool,
    allow_chat: true
  )

  if content.empty?
    puts "  ⚠️  Content is empty (tool_calls present but not accessible)"
    puts "  💡 Use chat_raw() to access tool_calls"
  else
    puts "  ✅ Content: #{content[0..50]}..."
  end
rescue Ollama::Error => e
  puts "  ❌ Error: #{e.message}"
end

puts "\n--- Test 4: Full flow - Execute tool after getting tool_calls ---"
puts "Request: Get market quote for RELIANCE and execute it\n"

begin
  # Step 1: Get tool_calls from LLM
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("Get the market quote for RELIANCE stock on NSE")],
    tools: market_quote_tool,
    allow_chat: true
  )

  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "✅ Step 1: Tool call received from LLM"
    call = tool_calls.first
    puts "  Tool: #{call.name}"
    puts "  Arguments: #{call.arguments.inspect}\n"

    # Step 2: Execute the tool (finds instrument first, then calls API)
    args = call.arguments
    symbol = args["symbol"] || args[:symbol]
    exchange_segment = args["exchange_segment"] || args[:exchange_segment]

    puts "✅ Step 2: Executing tool..."
    puts "  Finding instrument: #{symbol} on #{exchange_segment}"

    begin
      # The tool will find instrument internally
      result = DhanHQDataTools.get_market_quote(
        symbol: symbol,
        exchange_segment: exchange_segment
      )

      if result[:error]
        puts "  ❌ Error: #{result[:error]}"
      else
        puts "  ✅ Instrument found and quote retrieved"
        quote = result[:result][:quote]
        if quote
          puts "  📊 Last Price: #{quote[:last_price]}"
          puts "  📊 Volume: #{quote[:volume]}"
          puts "  📊 OHLC: O=#{quote[:ohlc][:open]}, H=#{quote[:ohlc][:high]}, L=#{quote[:ohlc][:low]}, C=#{quote[:ohlc][:close]}"
        end
      end
    rescue StandardError => e
      puts "  ❌ Tool execution error: #{e.message}"
      puts "  Note: This is expected if DhanHQ is not configured or market is closed"
    end

    # Step 3: Feed result back to LLM (optional - for multi-turn)
    puts "\n✅ Step 3: Tool result can be fed back to LLM for next turn"
    puts "  (This would be done automatically by Executor)"

  else
    puts "⚠️  No tool calls detected"
  end
rescue Ollama::Error => e
  puts "❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
end

puts "\n--- Summary ---"
puts "✅ Use chat_raw() for tool calling - gives access to tool_calls"
puts "⚠️  Use chat() only for simple content responses (no tool_calls needed)"
puts "📝 Tool execution flow:"
puts "   1. LLM requests tool via chat_raw() → get tool_calls"
puts "   2. Find instrument using exchange_segment + symbol"
puts "   3. Execute tool with instrument"
puts "   4. Feed result back to LLM (if using Executor)"
puts "\n=== DONE ===\n"

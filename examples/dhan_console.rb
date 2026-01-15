#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/ollama_client"
require "tty-reader"
require "tty-screen"
require "tty-cursor"
require "dhan_hq"
require_relative "dhanhq_tools"

def build_config
  config = Ollama::Config.new
  config.base_url = ENV["OLLAMA_BASE_URL"] if ENV["OLLAMA_BASE_URL"]
  config.model = ENV["OLLAMA_MODEL"] if ENV["OLLAMA_MODEL"]
  config.temperature = ENV["OLLAMA_TEMPERATURE"].to_f if ENV["OLLAMA_TEMPERATURE"]
  config
end

def exit_command?(text)
  %w[/exit /quit exit quit].include?(text.downcase)
end

def system_prompt_from_env
  system_prompt = ENV.fetch("OLLAMA_SYSTEM", nil)
  return nil unless system_prompt && !system_prompt.strip.empty?

  system_prompt
end

def print_banner(config)
  puts "DhanHQ data console"
  puts "Model: #{config.model}"
  puts "Base URL: #{config.base_url}"
  puts "Type /exit to quit."
  puts "Screen: #{TTY::Screen.width}x#{TTY::Screen.height}"
  puts
end

HISTORY_PATH = ".ollama_dhan_history"
MAX_HISTORY = 200
COLOR_RESET = "\e[0m"
COLOR_USER = "\e[32m"
COLOR_LLM = "\e[36m"
USER_PROMPT = "#{COLOR_USER}you>#{COLOR_RESET} "
LLM_PROMPT = "#{COLOR_LLM}llm>#{COLOR_RESET} "

def build_reader
  TTY::Reader.new
end

def read_input(reader)
  reader.read_line(USER_PROMPT)
end

def load_history(reader, path)
  history = load_history_list(path)
  history.reverse_each { |line| reader.add_to_history(line) }
end

def load_history_list(path)
  return [] unless File.exist?(path)

  unique_history(normalize_history(File.readlines(path, chomp: true)))
end

def normalize_history(lines)
  lines.map(&:strip).reject(&:empty?)
end

def unique_history(lines)
  seen = {}
  lines.each_with_object([]) do |line, unique|
    next if seen[line]

    unique << line
    seen[line] = true
  end
end

def update_history(path, text)
  history = load_history_list(path)
  history.delete(text)
  history.unshift(text)
  history = history.first(MAX_HISTORY)

  File.write(path, history.join("\n") + (history.empty? ? "" : "\n"))
end

def configure_dhanhq!
  DhanHQ.configure_with_env
  puts "✅ DhanHQ configured"
rescue StandardError => e
  puts "❌ DhanHQ configuration error: #{e.message}"
  puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
  exit 1
end

def tool_system_prompt
  <<~PROMPT
    You are a market data assistant. Use tools to answer user queries completely.

    Available tools with REQUIRED parameters:

    1. find_instrument(symbol: String) - REQUIRED: symbol
       - Find instrument details (exchange_segment, security_id) by symbol
       - Use this FIRST when you only have a symbol and need to resolve it
       - Returns: exchange_segment, security_id (numeric), trading_symbol, instrument_type

    2. get_market_quote(exchange_segment: String, symbol: String, security_id: Integer) - REQUIRED: exchange_segment, (symbol OR security_id)
       - Get full market quote (OHLC, depth, volume, etc.)
       - exchange_segment MUST be one of: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
       - symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE")
       - security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - Rate limit: 1 request per second
       - Up to 1000 instruments per request

    3. get_live_ltp(exchange_segment: String, symbol: String, security_id: Integer) - REQUIRED: exchange_segment, (symbol OR security_id)
       - Get Last Traded Price (LTP) - fastest API for current price
       - exchange_segment MUST be one of: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
       - symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE")
       - security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - Rate limit: 1 request per second
       - Up to 1000 instruments per request

    4. get_market_depth(exchange_segment: String, symbol: String, security_id: Integer) - REQUIRED: exchange_segment, (symbol OR security_id)
       - Get full market depth (bid/ask levels, order book)
       - exchange_segment MUST be one of: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
       - symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE")
       - security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - Rate limit: 1 request per second
       - Up to 1000 instruments per request

    5. get_historical_data(exchange_segment: String, from_date: String, to_date: String, symbol: String, security_id: Integer, interval: String, expiry_code: Integer, instrument: String) - REQUIRED: exchange_segment, from_date, to_date, (symbol OR security_id)
       - Get historical price data (OHLCV)
       - REQUIRED parameters:
         * exchange_segment: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
         * from_date: YYYY-MM-DD format (e.g., "2024-01-08")
         * to_date: YYYY-MM-DD format (non-inclusive, e.g., "2024-02-08")
         * symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE") OR
         * security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - OPTIONAL parameters:
         * interval: "1", "5", "15", "25", "60" (for intraday) - if provided, returns intraday data; if omitted, returns daily data
         * expiry_code: 0 (far month), 1 (near month), 2 (current month) - for derivatives
         * instrument: EQUITY, INDEX, FUTIDX, FUTSTK, OPTIDX, OPTSTK, FUTCOM, OPTFUT, FUTCUR, OPTCUR
       - Notes: Maximum 90 days for intraday, data available for last 5 years

    6a. get_expiry_list(exchange_segment: String, symbol: String, security_id: Integer) - REQUIRED: exchange_segment, (symbol OR security_id)
       - Get list of available expiry dates for an underlying instrument
       - REQUIRED parameters:
         * exchange_segment: For indices use "IDX_I", for stocks use "NSE_FNO" or "BSE_FNO"
         * symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE") OR
         * security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - Returns: Array of available expiry dates in "YYYY-MM-DD" format
       - For indices (NIFTY, BANKNIFTY): Use exchange_segment: "IDX_I" and INTEGER security_id from find_instrument (e.g., 13, not "NIFTY")
       - Rate limit: 1 request per 3 seconds
       - Use this tool first to get available expiries before calling get_option_chain

    6. get_option_chain(exchange_segment: String, symbol: String, security_id: Integer, expiry: String, strikes_count: Integer) - REQUIRED: exchange_segment, (symbol OR security_id), expiry
       - Get option chain for an underlying instrument for a specific expiry
       - REQUIRED parameters:
         * exchange_segment: For indices use "IDX_I", for stocks use "NSE_FNO" or "BSE_FNO"
         * symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE") OR
         * security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
         * expiry: YYYY-MM-DD format (REQUIRED - use get_expiry_list first to get available expiry dates)
       - OPTIONAL parameters:
         * strikes_count: Number of strikes to return around ATM (default: 5)
           - 3 strikes: 1 ITM, ATM, 1 OTM (minimal overview)
           - 5 strikes: 2 ITM, ATM, 2 OTM (recommended default - good for analysis)
           - 7 strikes: 3 ITM, ATM, 3 OTM (more detailed analysis)
           - 10+ strikes: More comprehensive view (larger response)
       - Returns: Option chain filtered to show strikes around ATM (ITM, ATM, OTM)
       - Note: Chain is automatically filtered to reduce response size - only strikes with both CE and PE are included
       - For indices (NIFTY, BANKNIFTY): Use exchange_segment: "IDX_I" and INTEGER security_id from find_instrument (e.g., 13, not "NIFTY")
       - Rate limit: 1 request per 3 seconds
       - CRITICAL WORKFLOW: If user asks for "next expiry", "upcoming expiry", "nearest expiry", or similar:
         1. First call get_expiry_list to get the expiry list
         2. Extract the FIRST expiry date from result.expiries array (this is the next/upcoming expiry)
         3. Use the EXACT expiry date string from result.expiries[0] - DO NOT invent, guess, or modify the date
         4. Call get_option_chain with that EXACT expiry date to get the actual option chain data
         5. Do NOT stop after getting the expiry list - you MUST fetch the actual chain data
       - Example: User asks "option chain of NIFTY for next expiry"
         Step 1: get_expiry_list(exchange_segment: "IDX_I", security_id: 13) → returns {result: {expiries: ["2026-01-20", "2026-01-27", ...]}}
         Step 2: get_option_chain(exchange_segment: "IDX_I", security_id: 13, expiry: "2026-01-20") → use the EXACT first date from the list
       - CRITICAL: If the expiry list shows ["2026-01-20", ...], use "2026-01-20", NOT "2024-12-26" or any other date you might think is correct
       - NEVER invent or guess expiry dates - ALWAYS copy the exact date string from result.expiries array

    7. get_expired_options_data(exchange_segment: String, expiry_date: String, symbol: String, security_id: Integer, interval: String, instrument: String, expiry_flag: String, expiry_code: Integer, strike: String, drv_option_type: String, required_data: Array) - REQUIRED: exchange_segment, expiry_date, (symbol OR security_id)
       - Get historical expired options data
       - REQUIRED parameters:
         * exchange_segment: NSE_FNO, BSE_FNO, NSE_EQ, BSE_EQ
         * expiry_date: YYYY-MM-DD format
         * symbol: Trading symbol string (e.g., "NIFTY", "RELIANCE") OR
         * security_id: MUST be an INTEGER (e.g., 13, 2885) - NEVER use a symbol string as security_id
       - OPTIONAL parameters (with defaults):
         * interval: "1", "5", "15", "25", "60" (default: "1")
         * instrument: "OPTIDX" (Index Options) or "OPTSTK" (Stock Options) - auto-detected if not provided
         * expiry_flag: "WEEK" or "MONTH" (default: "MONTH")
         * expiry_code: 0 (far), 1 (near), 2 (current) - default: 1 (near month)
         * strike: "ATM", "ATM+X", "ATM-X" (default: "ATM") - up to ATM+10/ATM-10 for index options, ATM+3/ATM-3 for others
         * drv_option_type: "CALL" or "PUT" (default: "CALL")
         * required_data: Array of fields like ["open", "high", "low", "close", "iv", "volume", "strike", "oi", "spot"] (default: all fields)
       - Notes: Maximum 31 days of data per request, historical data available for last 5 years

    EXCHANGE SEGMENTS (valid values):
    - IDX_I - Index
    - NSE_EQ - NSE Equity Cash
    - NSE_FNO - NSE Futures & Options
    - NSE_CURRENCY - NSE Currency
    - BSE_EQ - BSE Equity Cash
    - BSE_FNO - BSE Futures & Options
    - BSE_CURRENCY - BSE Currency
    - MCX_COMM - MCX Commodity

    INSTRUMENT TYPES (valid values):
    - EQUITY - Equity
    - INDEX - Index
    - FUTIDX - Futures Index
    - FUTSTK - Futures Stock
    - OPTIDX - Options Index
    - OPTSTK - Options Stock
    - FUTCOM - Futures Commodity
    - OPTFUT - Options Futures
    - FUTCUR - Futures Currency
    - OPTCUR - Options Currency

    WORKFLOW:
    - When you need to call multiple tools (e.g., find_instrument then get_live_ltp), call them in sequence.
    - After each tool call, use the EXACT values from the tool result to continue. Do not stop until you have fully answered the user's query.
    - CRITICAL: NEVER invent, guess, or modify values from tool results. ALWAYS use the exact values as returned.
    - If you called find_instrument and got a result like: {"result": {"exchange_segment": "IDX_I", "security_id": "13", "symbol": "NIFTY"}}
      Then for the next tool call, use:
      - exchange_segment: "IDX_I" (the exact string from result.exchange_segment)
      - security_id: 13 (the INTEGER value from result.security_id - convert string "13" to integer 13)
      - Do NOT use the symbol string "NIFTY" as security_id - security_id must be an INTEGER
    - Example: If find_instrument returns {"result": {"exchange_segment": "IDX_I", "security_id": "13", "symbol": "NIFTY"}}
      Then call get_option_chain with: exchange_segment: "IDX_I", security_id: 13 (integer, NOT the string "NIFTY" or "13")
    - CRITICAL: security_id must ALWAYS be an INTEGER (e.g., 13, 2885), NEVER a symbol string (e.g., "NIFTY", "RELIANCE")
    - CRITICAL: If result.security_id is a string (e.g., "13"), convert it to integer (13) before using as security_id parameter
    - CRITICAL: If get_expiry_list returns {"result": {"expiries": ["2026-01-20", "2026-01-27", ...]}}, use "2026-01-20" (the first date), NOT "2024-12-26" or any other date
    - NEVER invent dates, expiry values, or any other data - ALWAYS use exact values from tool results
    - CRITICAL FOR OPTION CHAIN: If user asks for "next expiry", "upcoming expiry", "nearest expiry", or "option chain" without specifying expiry:
      1. First call get_expiry_list to get the list of available expiry dates
      2. Extract the FIRST expiry date from result.expiries array (this is the next/upcoming expiry)
      3. Use the EXACT expiry date string from result.expiries[0] - DO NOT invent, guess, or modify the date
      4. Call get_option_chain with that EXACT expiry date to get the actual option chain data
      5. DO NOT stop after getting just the expiry list - you MUST fetch the actual chain data to answer the user's query
      6. Only provide your final answer after you have the actual option chain data, not just the expiry list
      7. CRITICAL EXAMPLE: If get_expiry_list returns {"result": {"expiries": ["2026-01-20", "2026-01-27", ...]}},
         you MUST use "2026-01-20" (the first date in the array), NOT "2024-12-26" or any other date
      8. NEVER invent or guess expiry dates - ALWAYS copy the exact date string from result.expiries array
      9. If the expiry list shows dates starting in 2026, use a 2026 date, NOT a 2024 date
    - Only provide your final answer after you have all the data needed to answer the user's question.
    - Indices like NIFTY, BANKNIFTY DO have options - they are index options. Use exchange_segment: IDX_I and the numeric security_id from find_instrument.

    CRITICAL RULES:
    - If the user provides ONLY a symbol (e.g., "RELIANCE", "TCS", "ltp of RELIANCE") WITHOUT exchange_segment, you MUST call find_instrument FIRST to get the correct exchange_segment and security_id.
    - If the user ALREADY provides exchange_segment (e.g., "get_market_quote for RELIANCE on exchange_segment NSE_EQ"), you can call the data tool directly - find_instrument is NOT needed.
    - NEVER guess or invent exchange_segment values. Valid values are: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    - NEVER use "NSE" or "BSE" alone - they are invalid. Always use full values like "NSE_EQ" or "BSE_EQ".
    - Common indices (NIFTY, BANKNIFTY, FINNIFTY, etc.) are found in IDX_I, not NSE_EQ.
    - DATE FORMATS: Always use YYYY-MM-DD format (e.g., "2024-01-08", not "01/08/2024" or "08-Jan-2024")
    - For historical data, to_date is NON-INCLUSIVE (end date is not included in results)
    - ERROR HANDLING: If a tool returns an error about invalid exchange_segment or missing required parameters, you MUST:
      1. Call find_instrument(symbol) to get the correct exchange_segment and security_id
      2. Verify all required parameters are provided with correct formats
      3. Retry the original tool call with the resolved parameters from find_instrument result
    - IMPORTANT: When you need to call a tool, actually CALL it using the tool_calls format. Do NOT output JSON descriptions of what you would call - the system will handle tool calls automatically.
    - Only call a tool when the user explicitly asks for market data, prices, quotes, option chains, or historical data.
    - If the user is greeting, chatting, or asking a general question, respond normally without calling tools.
    - When tools are used, fetch real data; do not invent values.
  PROMPT
end

def planning_system_prompt
  <<~PROMPT
    You are a planning assistant for a market data console.
    Analyze the user query and decide if tools are required to answer it.

    CRITICAL: If the query mentions any of these keywords or patterns, tools ARE needed:
    - "get_market_quote", "market quote", "quote"
    - "get_live_ltp", "LTP", "last traded price", "current price"
    - "get_market_depth", "market depth", "depth"
    - "get_historical_data", "historical", "price history", "candles", "OHLC"
    - "get_option_chain", "option chain", "options chain"
    - "get_expired_options", "expired options"
    - Any stock symbol (RELIANCE, TCS, INFY, etc.) with a request for data
    - Any request for real-time or historical market data

    Examples that NEED tools:
    - "get_market_quote for RELIANCE" → needs_tools: true, tools: [find_instrument, get_market_quote] (no exchange_segment provided)
    - "get_market_quote for RELIANCE on exchange_segment NSE_EQ" → needs_tools: true, tools: [get_market_quote] (exchange_segment already provided, skip find_instrument)
    - "What is the LTP of TCS?" → needs_tools: true, tools: [find_instrument, get_live_ltp] (no exchange_segment provided)
    - "ltp of RELIANCE" → needs_tools: true, tools: [find_instrument, get_live_ltp] (no exchange_segment provided)
    - "Show me historical data for INFY from 2024-01-01 to 2024-01-31" → needs_tools: true, tools: [find_instrument, get_historical_data] (requires from_date and to_date in YYYY-MM-DD format)
    - "Get option chain for NIFTY" → needs_tools: true, tools: [find_instrument, get_option_chain] (no exchange_segment provided)

    REQUIRED PARAMETERS SUMMARY:
    - find_instrument: REQUIRED - symbol
    - get_market_quote: REQUIRED - exchange_segment, (symbol OR security_id)
    - get_live_ltp: REQUIRED - exchange_segment, (symbol OR security_id)
    - get_market_depth: REQUIRED - exchange_segment, (symbol OR security_id)
    - get_historical_data: REQUIRED - exchange_segment, from_date (YYYY-MM-DD), to_date (YYYY-MM-DD), (symbol OR security_id)
    - get_option_chain: REQUIRED - exchange_segment, (symbol OR security_id); OPTIONAL - expiry (YYYY-MM-DD)
    - get_expired_options_data: REQUIRED - exchange_segment, expiry_date (YYYY-MM-DD), (symbol OR security_id)

    CRITICAL RULES:
    - If the user provides ONLY a symbol (like "RELIANCE", "TCS", "NIFTY") WITHOUT exchange_segment, the workflow MUST be:
      1. First call find_instrument(symbol) to get exchange_segment and security_id
      2. Then call the data tool (get_live_ltp, get_market_quote, etc.) with the resolved exchange_segment
    - If the user ALREADY provides exchange_segment (e.g., "on exchange_segment NSE_EQ"), you can call the data tool directly - find_instrument is NOT needed.
    - For historical data, user MUST provide from_date and to_date in YYYY-MM-DD format
    - For option chain, if user provides expiry date, it must be in YYYY-MM-DD format
    - For expired options data, user MUST provide expiry_date in YYYY-MM-DD format

    Valid exchange_segment values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    NEVER use "NSE" or "BSE" alone - they are invalid. Use "NSE_EQ" or "BSE_EQ" instead.
    Common indices (NIFTY, BANKNIFTY, FINNIFTY, etc.) use IDX_I, not NSE_EQ.

    Examples that DO NOT need tools:
    - "Hi", "Hello", "How are you?" → needs_tools: false
    - "What is a stock?" → needs_tools: false (general knowledge)
    - "Explain options trading" → needs_tools: false (educational)

    If tools are needed, specify which tool(s) and what parameters are required, including date formats (YYYY-MM-DD).
  PROMPT
end

def planning_schema
  {
    "type" => "object",
    "required" => ["needs_tools", "reasoning", "tool_requests"],
    "properties" => {
      "needs_tools" => { "type" => "boolean" },
      "reasoning" => { "type" => "string" },
      "tool_requests" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "required" => ["name", "purpose"],
          "properties" => {
            "name" => { "type" => "string" },
            "purpose" => { "type" => "string" },
            "args_hint" => { "type" => "string" }
          }
        }
      }
    }
  }
end

def build_tools
  {
    "find_instrument" => lambda do |symbol:|
      DhanHQDataTools.find_instrument(**compact_kwargs(symbol: symbol))
    end,
    "get_market_quote" => lambda do |exchange_segment:, symbol: nil, security_id: nil|
      DhanHQDataTools.get_market_quote(**compact_kwargs(exchange_segment: exchange_segment,
                                                        symbol: symbol,
                                                        security_id: security_id))
    end,
    "get_live_ltp" => lambda do |exchange_segment:, symbol: nil, security_id: nil|
      DhanHQDataTools.get_live_ltp(**compact_kwargs(exchange_segment: exchange_segment,
                                                    symbol: symbol,
                                                    security_id: security_id))
    end,
    "get_market_depth" => lambda do |exchange_segment:, symbol: nil, security_id: nil|
      DhanHQDataTools.get_market_depth(**compact_kwargs(exchange_segment: exchange_segment,
                                                        symbol: symbol,
                                                        security_id: security_id))
    end,
    "get_historical_data" => lambda do |exchange_segment:, from_date:, to_date:, symbol: nil, security_id: nil,
                                        interval: nil, expiry_code: nil|
      DhanHQDataTools.get_historical_data(**compact_kwargs(exchange_segment: exchange_segment,
                                                           symbol: symbol,
                                                           security_id: security_id,
                                                           from_date: from_date,
                                                           to_date: to_date,
                                                           interval: interval,
                                                           expiry_code: expiry_code))
    end,
    "get_expiry_list" => lambda do |exchange_segment:, symbol: nil, security_id: nil|
      # Convert security_id to integer if provided (LLM may pass it as string)
      normalized_security_id = security_id ? security_id.to_i : nil
      DhanHQDataTools.get_expiry_list(**compact_kwargs(exchange_segment: exchange_segment,
                                                       symbol: symbol,
                                                       security_id: normalized_security_id))
    end,
    "get_option_chain" => lambda do |exchange_segment:, symbol: nil, security_id: nil, expiry: nil, strikes_count: 5|
      # Convert security_id to integer if provided (LLM may pass it as string)
      normalized_security_id = security_id ? security_id.to_i : nil
      # Default to 5 strikes (2 ITM, ATM, 2 OTM) - good balance for analysis
      normalized_strikes_count = strikes_count.to_i
      normalized_strikes_count = 5 if normalized_strikes_count < 1 # Minimum 1 (ATM)
      DhanHQDataTools.get_option_chain(**compact_kwargs(exchange_segment: exchange_segment,
                                                        symbol: symbol,
                                                        security_id: normalized_security_id,
                                                        expiry: expiry,
                                                        strikes_count: normalized_strikes_count))
    end,
    "get_expired_options_data" => lambda do |exchange_segment:, expiry_date:, symbol: nil, security_id: nil,
                                             interval: nil, instrument: nil, expiry_flag: nil, expiry_code: nil,
                                             strike: nil, drv_option_type: nil, required_data: nil|
      DhanHQDataTools.get_expired_options_data(
        **compact_kwargs(exchange_segment: exchange_segment,
                         expiry_date: expiry_date,
                         symbol: symbol,
                         security_id: security_id,
                         interval: interval,
                         instrument: instrument,
                         expiry_flag: expiry_flag,
                         expiry_code: expiry_code,
                         strike: strike,
                         drv_option_type: drv_option_type,
                         required_data: required_data)
      )
    end
  }
end

def compact_kwargs(kwargs)
  kwargs.reject { |_, value| value.nil? || value == "" }
end

def tool_messages(messages)
  messages.select { |message| message[:role] == "tool" }
end

def print_tool_results(messages)
  puts "Tool Results:"
  tool_messages(messages).each do |message|
    print_tool_message(message)
  end
end

def print_tool_message(message)
  tool_name = message[:name] || "unknown_tool"
  puts "- #{tool_name}"
  puts format_tool_content(message[:content])
end

def format_tool_content(content)
  parsed = parse_tool_content(content)
  return parsed if parsed.is_a?(String)

  JSON.pretty_generate(parsed)
end

def parse_tool_content(content)
  return content unless content.is_a?(String)

  JSON.parse(content)
rescue JSON::ParserError
  content
end

def show_llm_summary?
  ENV["SHOW_LLM_SUMMARY"] == "true"
end

def allow_no_tool_output?
  ENV["ALLOW_NO_TOOL_OUTPUT"] != "false"
end

def show_plan?
  ENV["SHOW_PLAN"] == "true"
end

def print_hallucination_warning
  puts "No tool results were produced."
  puts "LLM output suppressed to avoid hallucinated data."
end

def query_requires_tools?(query)
  tool_keywords = [
    "get_market_quote", "market quote", "quote",
    "get_live_ltp", "ltp", "last traded price", "current price",
    "get_market_depth", "market depth", "depth",
    "get_historical_data", "historical", "price history", "candles", "ohlc",
    "get_option_chain", "option chain", "options chain",
    "get_expired_options", "expired options"
  ]

  query_lower = query.downcase
  tool_keywords.any? { |keyword| query_lower.include?(keyword) }
end

def plan_for_query(client, query, config)
  response = client.chat_raw(
    messages: [
      { role: "system", content: planning_system_prompt },
      { role: "user", content: query }
    ],
    allow_chat: true,
    format: planning_schema,
    options: { temperature: config.temperature }
  )

  plan = parse_tool_content(response.message&.content.to_s)

  if !plan["needs_tools"] && query_requires_tools?(query)
    plan["needs_tools"] = true
    plan["reasoning"] = "Query contains tool-related keywords that require data retrieval."
  end

  plan
end

def print_plan(plan)
  return unless show_plan?

  puts "Plan:"
  puts "- Needs tools: #{plan['needs_tools']}"
  puts "- Reasoning: #{plan['reasoning']}"
  return if plan["tool_requests"].empty?

  puts "- Tool requests:"
  plan["tool_requests"].each do |request|
    args_hint = request["args_hint"]
    suffix = args_hint && !args_hint.empty? ? " (#{args_hint})" : ""
    puts "  - #{request['name']}: #{request['purpose']}#{suffix}"
  end
end

def chat_response(client, messages, config)
  content = +""
  print LLM_PROMPT

  client.chat_raw(
    messages: messages,
    allow_chat: true,
    options: { temperature: config.temperature },
    stream: true
  ) do |chunk|
    token = chunk.dig("message", "content").to_s
    next if token.empty?

    content << token
    print token
  end

  puts
  content
end

class ConsoleStream
  def initialize
    @started = false
  end

  def emit(event, text: nil, **)
    return unless event == :token && text

    unless @started
      print LLM_PROMPT
      @started = true
    end
    print text
  end

  def finish
    puts if @started
  end
end

def run_console(client, config)
  configure_dhanhq!
  print_banner(config)
  reader = build_reader
  load_history(reader, HISTORY_PATH)
  tools = build_tools
  system_prompt = [tool_system_prompt, system_prompt_from_env].compact.join("\n\n")
  chat_messages = []
  system_prompt_from_env&.then { |prompt| chat_messages << { role: "system", content: prompt } }

  loop do
    input = read_input(reader)
    break unless input

    text = input.strip
    next if text.empty?
    break if exit_command?(text)

    update_history(HISTORY_PATH, text)
    plan = plan_for_query(client, text, config)
    print_plan(plan)

    unless plan["needs_tools"]
      chat_messages << { role: "user", content: text }
      content = chat_response(client, chat_messages, config)
      chat_messages << { role: "assistant", content: content }
      next
    end

    stream = show_llm_summary? ? ConsoleStream.new : nil
    executor = Ollama::Agent::Executor.new(client, tools: tools, max_steps: 10, stream: stream)
    result = executor.run(system: system_prompt, user: text)
    stream&.finish

    if tool_messages(executor.messages).empty?
      if allow_no_tool_output?
        puts "No tool results were produced."
        print LLM_PROMPT
        puts result
      else
        print_hallucination_warning
      end
    else
      print_tool_results(executor.messages)
      print LLM_PROMPT
      puts result
    end
  end
rescue Interrupt
  puts "\nExiting..."
end

config = build_config
client = Ollama::Client.new(config: config)
run_console(client, config)

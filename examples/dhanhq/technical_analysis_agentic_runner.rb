#!/usr/bin/env ruby
# frozen_string_literal: true

# True Agentic Technical Analysis Runner
# Uses Ollama::Agent::Executor for dynamic tool calling
# LLM decides which tools to call and when, based on results

require "json"
require "date"
require "dhan_hq"
require_relative "../../lib/ollama_client"
require_relative "../dhanhq_tools"

# Load all modules
require_relative "utils/instrument_helper"
require_relative "utils/rate_limiter"
require_relative "utils/parameter_normalizer"
require_relative "utils/parameter_cleaner"
require_relative "utils/trading_parameter_normalizer"
require_relative "builders/market_context_builder"
require_relative "schemas/agent_schemas"
require_relative "services/base_service"
require_relative "services/data_service"
require_relative "services/trading_service"
require_relative "indicators/technical_indicators"
require_relative "analysis/market_structure"
require_relative "analysis/pattern_recognizer"
require_relative "analysis/trend_analyzer"
require_relative "agents/base_agent"
require_relative "agents/data_agent"
require_relative "agents/trading_agent"
require_relative "agents/technical_analysis_agent"
require_relative "agents/orchestrator_agent"
require_relative "scanners/swing_scanner"
require_relative "scanners/intraday_options_scanner"

module DhanHQ
  # Main agent orchestrator
  class Agent
    def initialize(ollama_client: nil, trading_ollama_client: nil)
      @ollama_client = ollama_client || Ollama::Client.new
      @trading_ollama_client = trading_ollama_client || create_trading_client
      @data_agent = Agents::DataAgent.new(ollama_client: @ollama_client)
      @trading_agent = Agents::TradingAgent.new(ollama_client: @trading_ollama_client)
      @analysis_agent = Agents::TechnicalAnalysisAgent.new(ollama_client: @ollama_client)
      @orchestrator_agent = Agents::OrchestratorAgent.new(ollama_client: @ollama_client)
      @swing_scanner = Scanners::SwingScanner.new
      @options_scanner = Scanners::IntradayOptionsScanner.new
    end

    attr_reader :data_agent, :trading_agent, :analysis_agent, :orchestrator_agent, :swing_scanner, :options_scanner

    private

    def create_trading_client
      config = Ollama::Config.new
      config.timeout = 60
      Ollama::Client.new(config: config)
    end
  end
end

# Configure DhanHQ
begin
  DhanHQ.configure_with_env
  puts "✅ DhanHQ configured"
rescue StandardError => e
  puts "⚠️  DhanHQ configuration error: #{e.message}"
  puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
  exit 1
end

puts "=" * 60
puts "TECHNICAL ANALYSIS - TRUE AGENTIC TOOL CALLING"
puts "=" * 60
puts

# Initialize agent
agent = DhanHQ::Agent.new

# Define tools using structured Tool classes for better type safety and LLM understanding
# This provides explicit schemas with descriptions, types, and enums

# Swing Scan Tool - Structured definition
swing_scan_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "swing_scan",
    description: "Scans for swing trading opportunities in EQUITY STOCKS only. " \
                 "Use for stocks like RELIANCE, TCS, INFY, HDFC. " \
                 "Do NOT use for indices (NIFTY, SENSEX, BANKNIFTY).",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Stock symbol to scan (e.g., RELIANCE, TCS, INFY). Must be a stock, not an index."
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment (default: NSE_EQ)",
          enum: %w[NSE_EQ BSE_EQ]
        ),
        min_score: Ollama::Tool::Function::Parameters::Property.new(
          type: "integer",
          description: "Minimum score threshold (default: 40)"
        ),
        verbose: Ollama::Tool::Function::Parameters::Property.new(
          type: "boolean",
          description: "Verbose output (default: false)"
        )
      },
      required: %w[symbol]
    )
  )
)

# Options Scan Tool - Structured definition
options_scan_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "options_scan",
    description: "Scans for intraday options buying opportunities in INDICES only. " \
                 "Use for NIFTY, SENSEX, BANKNIFTY. Do NOT use for stocks.",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Index symbol (NIFTY, SENSEX, or BANKNIFTY). Must be an index, not a stock.",
          enum: %w[NIFTY SENSEX BANKNIFTY]
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment (default: IDX_I)",
          enum: %w[IDX_I]
        ),
        min_score: Ollama::Tool::Function::Parameters::Property.new(
          type: "integer",
          description: "Minimum score threshold (default: 40)"
        ),
        verbose: Ollama::Tool::Function::Parameters::Property.new(
          type: "boolean",
          description: "Verbose output (default: false)"
        )
      },
      required: %w[symbol]
    )
  )
)

# Technical Analysis Tool - Structured definition
technical_analysis_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "technical_analysis",
    description: "Performs full technical analysis including trend, indicators, and patterns. " \
                 "Can be used for both stocks and indices.",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        symbol: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Symbol to analyze (stock or index)"
        ),
        exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Exchange segment (default: NSE_EQ)",
          enum: %w[NSE_EQ BSE_EQ NSE_FNO BSE_FNO IDX_I]
        )
      },
      required: %w[symbol]
    )
  )
)

# Define tools with structured Tool classes and callables
tools = {
  "swing_scan" => {
    tool: swing_scan_tool,
    callable: lambda do |symbol:, exchange_segment: "NSE_EQ", min_score: 40, verbose: false|
      # CRITICAL: Only allow equity stocks, not indices
      if %w[NIFTY SENSEX BANKNIFTY].include?(symbol.to_s.upcase)
        return { error: "#{symbol} is an index, not a stock. Use options_scan for indices." }
      end

      begin
        candidates = agent.swing_scanner.scan_symbols(
          [symbol.to_s],
          exchange_segment: exchange_segment.to_s,
          min_score: min_score.to_i,
          verbose: verbose
        )

        {
          symbol: symbol,
          exchange_segment: exchange_segment,
          candidates_found: candidates.length,
          candidates: candidates.map do |c|
            {
              symbol: c[:symbol],
              score: c[:score],
              trend: c[:analysis][:trend][:trend],
              recommendation: c[:recommendation]
            }
          end
        }
      rescue StandardError => e
        { error: e.message, backtrace: e.backtrace.first(3) }
      end
    end
  },

  "options_scan" => {
    tool: options_scan_tool,
    callable: lambda do |symbol:, exchange_segment: "IDX_I", min_score: 40, verbose: false|
      # CRITICAL: Only allow indices, not stocks
      unless %w[NIFTY SENSEX BANKNIFTY].include?(symbol.to_s.upcase)
        error_message = "#{symbol} is not an index. Use swing_scan for stocks. " \
                        "Options are only available for indices (NIFTY, SENSEX, BANKNIFTY)."
        return { error: error_message }
      end

      begin
        options_setups = agent.options_scanner.scan_for_options_setups(
          symbol.to_s,
          exchange_segment: exchange_segment.to_s,
          min_score: min_score.to_i,
          verbose: verbose
        )

        if options_setups[:error]
          { error: options_setups[:error] }
        else
          underlying_price = options_setups.dig(:underlying_analysis, :current_price)
          {
            symbol: symbol,
            exchange_segment: exchange_segment,
            underlying_price: underlying_price,
            setups_found: options_setups[:setups]&.length || 0,
            setups: options_setups[:setups]&.map do |s|
              {
                type: s[:type],
                strike: s[:strike],
                score: s[:score],
                iv: s[:iv],
                ltp: s[:ltp],
                recommendation: s[:recommendation]
              }
            end || []
          }
        end
      rescue StandardError => e
        { error: e.message, backtrace: e.backtrace.first(3) }
      end
    end
  },

  "technical_analysis" => {
    tool: technical_analysis_tool,
    callable: lambda do |symbol:, exchange_segment: "NSE_EQ"|
      analysis_result = agent.analysis_agent.analyze_symbol(
        symbol: symbol.to_s,
        exchange_segment: exchange_segment.to_s
      )

      if analysis_result[:error]
        { error: analysis_result[:error] }
      else
        analysis = analysis_result[:analysis]
        {
          symbol: symbol,
          exchange_segment: exchange_segment,
          trend: analysis[:trend]&.dig(:trend),
          trend_strength: analysis[:trend]&.dig(:strength),
          rsi: analysis[:indicators]&.dig(:rsi)&.round(2),
          macd: analysis[:indicators]&.dig(:macd)&.round(2),
          current_price: analysis[:current_price],
          patterns_count: analysis[:patterns]&.dig(:candlestick)&.length || 0,
          structure_break: analysis[:structure_break]&.dig(:broken) || false
        }
      end
    rescue StandardError => e
      { error: e.message, backtrace: e.backtrace.first(3) }
    end
  }
}

# Get user query and market context
user_query = ARGV[0] || "Analyze SENSEX and find swing trading opportunities"
market_context = ARGV[1] || "Current market: SENSEX, NIFTY and RELIANCE are active. Looking for trading opportunities."

puts "🤔 Agentic Analysis - LLM will decide which tools to call dynamically"
puts "─" * 60
puts "User Query: #{user_query}"
puts "Market Context: #{market_context}"
puts

# Build system prompt
system_prompt = <<~PROMPT
  You are a trading analysis agent. Your job is to help users analyze markets and find trading opportunities.

  Available Tools:
  1. swing_scan(symbol, exchange_segment="NSE_EQ", min_score=40, verbose=false)
     - Scans for swing trading opportunities in EQUITY STOCKS only
     - Use for: RELIANCE, TCS, INFY, HDFC, etc. (stocks, not indices)
     - Returns: List of swing candidates with scores
     - CRITICAL: Do NOT use for indices (NIFTY, SENSEX, BANKNIFTY)

  2. options_scan(symbol, exchange_segment="IDX_I", min_score=40, verbose=false)
     - Scans for intraday options buying opportunities in INDICES only
     - Use for: NIFTY, SENSEX, BANKNIFTY (indices, not stocks)
     - Returns: List of options setups (calls/puts) with scores
     - CRITICAL: Do NOT use for stocks (RELIANCE, TCS, etc.)

  3. technical_analysis(symbol, exchange_segment="NSE_EQ")
     - Performs full technical analysis (trend, indicators, patterns)
     - Can be used for both stocks and indices
     - Returns: Complete technical analysis results

  Rules:
  - For swing trading: Use swing_scan ONLY on equity stocks (NSE_EQ, BSE_EQ)
  - For options: Use options_scan ONLY on indices (IDX_I) like NIFTY, SENSEX, BANKNIFTY
  - You can call multiple tools in sequence
  - Use tool results to decide what to do next
  - If a tool returns an error, try a different approach or inform the user

  Market Context: #{market_context}
PROMPT

user_prompt = user_query

# Create executor with tools
executor = Ollama::Agent::Executor.new(
  Ollama::Client.new,
  tools: tools,
  max_steps: 20
)

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

def print_llm_summary(result)
  return unless ENV["SHOW_LLM_SUMMARY"] == "true"

  puts
  puts "LLM Summary (unverified):"
  puts result
end

def print_hallucination_warning
  puts "No tool results were produced."
  puts "LLM output suppressed to avoid hallucinated data."
end

# Run the agentic loop
begin
  puts "🔄 Starting agentic tool-calling loop..."
  puts

  result = executor.run(
    system: system_prompt,
    user: user_prompt
  )

  puts
  puts "=" * 60
  puts "Agentic Analysis Complete"
  puts "=" * 60
  if tool_messages(executor.messages).empty?
    print_hallucination_warning
  else
    print_tool_results(executor.messages)
    print_llm_summary(result)
  end
rescue Ollama::Error => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
rescue StandardError => e
  puts "❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# Technical Analysis Runner - Run only technical analysis examples
# Usage: ruby examples/dhanhq/technical_analysis_runner.rb

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

# Load the Agent class definition
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
  puts "   Continuing with mock data for demonstration..."
end

puts "=" * 60
puts "TECHNICAL ANALYSIS - LLM-POWERED ORCHESTRATION"
puts "=" * 60
puts

# Helper methods (defined before use)
def perform_technical_analysis(agent, symbol, exchange_segment)
  analysis_result = agent.analysis_agent.analyze_symbol(
    symbol: symbol,
    exchange_segment: exchange_segment
  )

  return log_analysis_error(analysis_result) if analysis_result[:error]

  analysis = analysis_result[:analysis]
  return log_analysis_empty if analysis.nil? || analysis.empty?

  log_analysis_summary(analysis)
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

def perform_swing_scan(agent, symbol, exchange_segment)
  candidates = agent.swing_scanner.scan_symbols(
    [symbol],
    exchange_segment: exchange_segment,
    min_score: 40,
    verbose: false
  )

  if candidates.empty?
    puts "   ⚠️  No swing candidates found (score < 40)"
  else
    candidate = candidates.first
    puts "   ✅ Swing Candidate Found"
    puts "   📈 Score: #{candidate[:score]}/100"
    puts "   📊 Trend: #{candidate[:analysis][:trend][:trend]}"
    puts "   💡 #{candidate[:recommendation] || 'Analysis complete'}"
  end
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

def perform_options_scan(agent, symbol, exchange_segment)
  options_setups = agent.options_scanner.scan_for_options_setups(
    symbol,
    exchange_segment: exchange_segment,
    min_score: 40,
    verbose: true
  )

  if options_setups[:error]
    puts "   ⚠️  #{options_setups[:error]}"
  elsif options_setups[:setups] && !options_setups[:setups].empty?
    puts "   ✅ Found #{options_setups[:setups].length} options setups"
    options_setups[:setups].first(3).each do |setup|
      puts "      📊 #{setup[:type].to_s.upcase} @ #{setup[:strike]}: Score #{setup[:score]}/100"
    end
  else
    puts "   ⚠️  No options setups found (min_score: 40)"
    puts "      Try lowering min_score or check verbose output above for details"
  end
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
end

# Initialize agent
agent = DhanHQ::Agent.new

# ============================================================
# LLM-POWERED ORCHESTRATION
# ============================================================
puts "🤔 Letting LLM decide what to analyze..."
puts "─" * 60

# Get market context first (can be fetched from real data)
market_context = ARGV[1] || "Current market: SENSEX, NIFTY and RELIANCE are active. Looking for trading opportunities."

user_query = ARGV[0] || "Analyze SENSEX and find swing trading opportunities"

puts "User Query: #{user_query}"
puts "Market Context: #{market_context}"
puts

begin
  plan = agent.orchestrator_agent.decide_analysis_plan(
    market_context: market_context,
    user_query: user_query
  )

  if plan[:error]
    puts "   ⚠️  Error creating plan: #{plan[:error]}"
    puts "   Falling back to default analysis..."
    plan = {
      "analysis_plan" => [
        { "symbol" => "RELIANCE", "exchange_segment" => "NSE_EQ", "analysis_type" => "technical_analysis",
          "priority" => 1 },
        { "symbol" => "TCS", "exchange_segment" => "NSE_EQ", "analysis_type" => "swing_scan", "priority" => 2 },
        { "symbol" => "NIFTY", "exchange_segment" => "IDX_I", "analysis_type" => "options_scan", "priority" => 3 }
      ],
      "reasoning" => "Default fallback plan"
    }
  end

  puts "📋 Analysis Plan:"
  puts "   Reasoning: #{plan['reasoning'] || 'N/A'}"
  puts "   Tasks: #{plan['analysis_plan']&.length || 0} analysis tasks"
  puts

  # Sort by priority
  tasks = (plan["analysis_plan"] || []).sort_by { |t| t["priority"] || 999 }

  tasks.each_with_index do |task, idx|
    symbol = task["symbol"]
    exchange_segment = task["exchange_segment"]
    analysis_type = task["analysis_type"]

    puts "=" * 60
    puts "Task #{idx + 1}: #{analysis_type} for #{symbol} (#{exchange_segment})"
    puts "─" * 60

    if analysis_type == "all"
      perform_technical_analysis(agent, symbol, exchange_segment)
      perform_swing_scan(agent, symbol, exchange_segment)
      perform_options_scan(agent, symbol, exchange_segment)
    else
      case analysis_type
      when "technical_analysis"
        perform_technical_analysis(agent, symbol, exchange_segment)
      when "swing_scan"
        perform_swing_scan(agent, symbol, exchange_segment)
      when "options_scan"
        perform_options_scan(agent, symbol, exchange_segment)
      end
    end

    puts
  end
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
end

def log_analysis_error(analysis_result)
  puts "   ⚠️  Error: #{analysis_result[:error]}"
end

def log_analysis_empty
  puts "   ⚠️  Error: Analysis returned empty result"
end

def log_analysis_summary(analysis)
  puts "   ✅ Analysis Complete"
  puts trend_summary_text(analysis)
  puts rsi_summary_text(analysis)
  puts macd_summary_text(analysis)
  puts current_price_text(analysis)
  puts patterns_summary_text(analysis)
  puts structure_break_text(analysis)
end

def trend_summary_text(analysis)
  trend = analysis[:trend] || {}
  trend_name = trend[:trend] || "N/A"
  strength = trend[:strength] || 0
  "   📊 Trend: #{trend_name} (#{strength}% strength)"
end

def rsi_summary_text(analysis)
  rsi = analysis[:indicators]&.dig(:rsi)
  rsi_text = rsi ? rsi.round(2) : "N/A"
  "   📊 RSI: #{rsi_text}"
end

def macd_summary_text(analysis)
  macd = analysis[:indicators]&.dig(:macd)
  macd_text = macd ? macd.round(2) : "N/A"
  "   📊 MACD: #{macd_text}"
end

def current_price_text(analysis)
  current_price = analysis[:current_price] || "N/A"
  "   📊 Current Price: #{current_price}"
end

def patterns_summary_text(analysis)
  candlestick_patterns = analysis[:patterns]&.dig(:candlestick) || []
  "   📊 Patterns: #{candlestick_patterns.length} patterns"
end

def structure_break_text(analysis)
  broken = analysis[:structure_break]&.dig(:broken)
  "   📊 Structure Break: #{broken ? 'Yes' : 'No'}"
end

def format_score_breakdown(details)
  "Trend=#{details[:trend]}, RSI=#{details[:rsi]}, MACD=#{details[:macd]}, " \
    "Structure=#{details[:structure]}, Patterns=#{details[:patterns]}"
end

def format_option_setup_details(setup)
  iv = setup[:iv]&.round(2) || "N/A"
  oi = setup[:oi] || "N/A"
  volume = setup[:volume] || "N/A"
  "IV: #{iv}% | OI: #{oi} | Volume: #{volume}"
end

# Uncomment below to also run manual examples for comparison
if ENV["SHOW_MANUAL_EXAMPLES"] == "true"
  puts "=" * 60
  puts "TECHNICAL ANALYSIS EXAMPLES (Manual - for comparison)"
  puts "=" * 60
  puts

  # ============================================================
  # MANUAL EXAMPLES (for comparison)
  # ============================================================
  puts "Example 1: Technical Analysis for RELIANCE"
  puts "─" * 60

  begin
    analysis_result = agent.analysis_agent.analyze_symbol(
      symbol: "RELIANCE",
      exchange_segment: "NSE_EQ"
    )

    if analysis_result[:error]
      puts "   ⚠️  Error: #{analysis_result[:error]}"
    elsif analysis_result[:analysis].nil? || analysis_result[:analysis].empty?
      puts "   ⚠️  Error: Analysis returned empty result"
    else
      analysis = analysis_result[:analysis]
      puts "   ✅ Analysis Complete"
      puts "   📊 Trend: #{analysis[:trend]&.dig(:trend) || 'N/A'} (#{analysis[:trend]&.dig(:strength) || 0}% strength)"
      puts "   📊 RSI: #{analysis[:indicators]&.dig(:rsi)&.round(2) || 'N/A'}"
      puts "   📊 MACD: #{analysis[:indicators]&.dig(:macd)&.round(2) || 'N/A'}"
      puts "   📊 Current Price: #{analysis[:current_price] || 'N/A'}"
      puts "   📊 Patterns Detected: #{analysis[:patterns]&.dig(:candlestick)&.length || 0} candlestick patterns"
      puts "   📊 Structure Break: #{analysis[:structure_break]&.dig(:broken) ? 'Yes' : 'No'}"

      # Generate swing trading recommendation
      begin
        recommendation = agent.analysis_agent.generate_recommendation(
          analysis_result,
          trading_style: :swing
        )

        if recommendation && !recommendation[:error] && recommendation.is_a?(Hash)
          puts "\n   💡 Swing Trading Recommendation:"
          puts "      Action: #{recommendation['recommendation']&.upcase || 'N/A'}"
          puts "      Entry: #{recommendation['entry_price'] || 'N/A'}"
          puts "      Stop Loss: #{recommendation['stop_loss'] || 'N/A'}"
          puts "      Target: #{recommendation['target_price'] || 'N/A'}"
          puts "      Risk/Reward: #{recommendation['risk_reward_ratio']&.round(2) || 'N/A'}"
          puts "      Confidence: #{(recommendation['confidence'] * 100).round}%" if recommendation["confidence"]
        end
      rescue StandardError => e
        puts "   ⚠️  Could not generate recommendation: #{e.message}"
      end
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
  end

  puts
  puts "Example 2: Swing Trading Scanner"
  puts "─" * 60

  begin
    # Scan a few symbols for swing opportunities
    symbols_to_scan = ["RELIANCE", "TCS", "INFY"]
    puts "   🔍 Scanning #{symbols_to_scan.length} symbols for swing opportunities..."

    candidates = agent.swing_scanner.scan_symbols(
      symbols_to_scan,
      exchange_segment: "NSE_EQ",
      min_score: 40,
      verbose: true
    )

    if candidates.empty?
      puts "   ⚠️  No swing candidates found above minimum score (40/100)"
      puts "      Try lowering min_score or check rejected candidates above"
    else
      puts "   ✅ Found #{candidates.length} swing candidates:"
      candidates.each do |candidate|
        puts "      📈 #{candidate[:symbol]}: Score #{candidate[:score]}/100"
        if candidate[:score_details]
          details = candidate[:score_details]
          puts "         Breakdown: #{format_score_breakdown(details)}"
        end
        trend = candidate[:analysis][:trend]
        puts "         Trend: #{trend[:trend]} (#{trend[:strength]}% strength)"
        puts "         #{candidate[:interpretation]}"
      end
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
  end

  puts
  puts "Example 3: Intraday Options Scanner"
  puts "─" * 60

  begin
    puts "   🔍 Scanning NIFTY for intraday options opportunities..."

    options_setups = agent.options_scanner.scan_for_options_setups(
      "NIFTY",
      exchange_segment: "IDX_I",
      min_score: 40,
      verbose: true
    )

    if options_setups[:error]
      puts "   ⚠️  #{options_setups[:error]}"
    elsif options_setups[:setups] && !options_setups[:setups].empty?
      puts "   ✅ Found #{options_setups[:setups].length} options setups:"
      options_setups[:setups].each do |setup|
        puts "      📊 #{setup[:type].to_s.upcase} @ #{setup[:strike]}"
        puts "         #{format_option_setup_details(setup)}"
        puts "         Score: #{setup[:score]}/100 | Recommendation: #{setup[:recommendation]}"
      end
    else
      puts "   ⚠️  No options setups found above minimum score (40/100)"
      puts "      Check rejected setups above or try lowering min_score"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
  end

end

puts
puts "=" * 60
puts "Technical Analysis Summary:"
puts "  ✅ Trend Analysis: Uptrend/Downtrend/Sideways detection"
puts "  ✅ Technical Indicators: RSI, MACD, Moving Averages, etc."
puts "  ✅ Pattern Recognition: Candlestick & Chart patterns"
puts "  ✅ Market Structure: SMC concepts, Order blocks, Liquidity zones"
puts "  ✅ Swing Trading Scanner: Find swing opportunities"
puts "  ✅ Intraday Options Scanner: Find options buying setups"
puts "  ✅ LLM Orchestration: AI decides what to analyze"
puts "=" * 60

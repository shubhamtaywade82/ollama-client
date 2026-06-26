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
    You are a market data assistant. Use ONLY the available tools for data.

    Available tools:
    - get_market_quote(exchange_segment, symbol|security_id)
    - get_live_ltp(exchange_segment, symbol|security_id)
    - get_market_depth(exchange_segment, symbol|security_id)
    - get_historical_data(exchange_segment, symbol|security_id, from_date, to_date, interval?, expiry_code?)
    - get_option_chain(exchange_segment, symbol|security_id, expiry?)
    - get_expired_options_data(exchange_segment, expiry_date, symbol|security_id, interval?, instrument?, expiry_flag?, expiry_code?, strike?, drv_option_type?, required_data?)

    Rules:
    - Call tools to fetch real data; do not invent values.
    - If a tool returns an error, explain the error and stop.
  PROMPT
end

def build_tools
  {
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
    "get_historical_data" => lambda do |exchange_segment:, symbol: nil, security_id: nil, from_date:, to_date:,
                                        interval: nil, expiry_code: nil|
      DhanHQDataTools.get_historical_data(**compact_kwargs(exchange_segment: exchange_segment,
                                                           symbol: symbol,
                                                           security_id: security_id,
                                                           from_date: from_date,
                                                           to_date: to_date,
                                                           interval: interval,
                                                           expiry_code: expiry_code))
    end,
    "get_option_chain" => lambda do |exchange_segment:, symbol: nil, security_id: nil, expiry: nil|
      DhanHQDataTools.get_option_chain(**compact_kwargs(exchange_segment: exchange_segment,
                                                        symbol: symbol,
                                                        security_id: security_id,
                                                        expiry: expiry))
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
  ENV["ALLOW_NO_TOOL_OUTPUT"] == "true"
end

def print_hallucination_warning
  puts "No tool results were produced."
  puts "LLM output suppressed to avoid hallucinated data."
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

  loop do
    input = read_input(reader)
    break unless input

    text = input.strip
    next if text.empty?
    break if exit_command?(text)

    update_history(HISTORY_PATH, text)
    stream = show_llm_summary? ? ConsoleStream.new : nil
    executor = Ollama::Agent::Executor.new(client, tools: tools, max_steps: 10, stream: stream)
    result = executor.run(system: system_prompt, user: text)
    stream&.finish

    if tool_messages(executor.messages).empty?
      if allow_no_tool_output?
        puts "No tool results were produced."
        puts "LLM output (unverified):" if show_llm_summary?
        puts result
      else
        print_hallucination_warning
      end
    else
      print_tool_results(executor.messages)
      puts result if show_llm_summary?
    end
  end
rescue Interrupt
  puts "\nExiting..."
end

config = build_config
client = Ollama::Client.new(config: config)
run_console(client, config)

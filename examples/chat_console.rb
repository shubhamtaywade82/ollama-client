#!/usr/bin/env ruby
# frozen_string_literal: true

# Load .env file if available (overload to ensure .env takes precedence over shell env)
begin
  require "dotenv"
  Dotenv.overload
rescue LoadError
  # dotenv not available, skip
end

require_relative "../lib/ollama_client"
require "tty-reader"
require "tty-screen"
require "tty-cursor"

def build_config
  config = Ollama::Config.new
  config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", config.model)
  config.temperature = ENV["OLLAMA_TEMPERATURE"].to_f if ENV["OLLAMA_TEMPERATURE"]
  config
end

def exit_command?(text)
  %w[/exit /quit exit quit].include?(text.downcase)
end

def add_system_message(messages)
  system_prompt = ENV.fetch("OLLAMA_SYSTEM", nil)
  return unless system_prompt && !system_prompt.strip.empty?

  messages << { role: "system", content: system_prompt }
end

def print_banner(config)
  puts "Ollama chat console"
  puts "Model: #{config.model}"
  puts "Base URL: #{config.base_url}"
  puts "Type /exit to quit."
  puts "Screen: #{TTY::Screen.width}x#{TTY::Screen.height}"
  puts
end

HISTORY_PATH = ".ollama_chat_history"
MAX_HISTORY = 200
COLOR_RESET = "\e[0m"
COLOR_USER = "\e[32m"
COLOR_LLM = "\e[36m"
USER_PROMPT = "#{COLOR_USER}you>#{COLOR_RESET} ".freeze
LLM_PROMPT = "#{COLOR_LLM}llm>#{COLOR_RESET} ".freeze

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

def chat_response(client, messages, config)
  content = +""
  prompt_printed = false

  print "#{COLOR_LLM}...#{COLOR_RESET}"
  $stdout.flush

  client.chat_raw(
    messages: messages,
    allow_chat: true,
    options: { temperature: config.temperature },
    stream: true
  ) do |chunk|
    token = chunk.dig("message", "content").to_s
    next if token.empty?

    unless prompt_printed
      print "\r#{LLM_PROMPT}"
      prompt_printed = true
    end

    content << token
    print token
    $stdout.flush
  end

  puts
  content
end

def run_console(client, config)
  messages = []
  add_system_message(messages)
  print_banner(config)
  reader = build_reader
  load_history(reader, HISTORY_PATH)

  loop do
    input = read_input(reader)
    break unless input

    text = input.strip
    next if text.empty?
    break if exit_command?(text)

    update_history(HISTORY_PATH, text)
    messages << { role: "user", content: text }
    content = chat_response(client, messages, config)
    messages << { role: "assistant", content: content }
  end
rescue Interrupt
  puts "\nExiting..."
end

config = build_config
client = Ollama::Client.new(config: config)
run_console(client, config)

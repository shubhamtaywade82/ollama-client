#!/usr/bin/env ruby
# frozen_string_literal: true

require "tty-prompt"
require "tty-markdown"
require "tty-spinner"
require "tty-cursor"
require "tty-screen"
require "pastel"
require "net/http"
require "json"
require "time"


# Configuration
OLLAMA_URL = URI("http://localhost:11434/api/chat")
OLLAMA_STREAM_URL = URI("http://localhost:11434/api/chat")
MODEL = "llama3.2:3b"

# Display mode: :streaming (real-time raw text) or :markdown (formatted at end)
DISPLAY_MODE = :streaming # Change to :streaming for real-time output

# System context/instructions for the model
# This provides context that the model will use for all responses
# Examples:
#   SYSTEM_CONTEXT = "You are a helpful Ruby programming assistant. Be concise and practical."
#   SYSTEM_CONTEXT = "You are analyzing financial data. Current market: Bullish. Key indicators: RSI 65."
#   SYSTEM_CONTEXT = nil # No system context
#   SYSTEM_CONTEXT_FILE = "examples/ollama-api.md" # Load context from a file

SYSTEM_CONTEXT = ENV.fetch("OLLAMA_SYSTEM", nil) # Can also be set via environment variable
SYSTEM_CONTEXT_FILE = ENV.fetch("OLLAMA_SYSTEM_FILE", "/home/nemesis/project/ollama-client/examples/ollama-api.md") # Path to markdown/text file to use as context

# UI Components
pastel = Pastel.new(enabled: true)
prompt = TTY::Prompt.new

# Color scheme
COLORS = {
  primary: :cyan,
  secondary: :blue,
  success: :green,
  warning: :yellow,
  error: :red,
  info: :magenta,
  dim: :bright_black
}.freeze

# Helper function to load context from file
def load_context_from_file(file_path)
  return nil unless file_path

  full_path = File.expand_path(file_path, __dir__)
  return nil unless File.exist?(full_path)

  File.read(full_path).strip
rescue StandardError => e
  warn "Warning: Could not load context file #{file_path}: #{e.message}"
  nil
end

# Message history for context
messages = []

# Initialize with system message if provided
# Priority: SYSTEM_CONTEXT_FILE > SYSTEM_CONTEXT > ENV
context_text = nil
if SYSTEM_CONTEXT_FILE
  context_text = load_context_from_file(SYSTEM_CONTEXT_FILE)
  if context_text
    puts "Loaded context from: #{SYSTEM_CONTEXT_FILE}"
  end
end

if !context_text && SYSTEM_CONTEXT && !SYSTEM_CONTEXT.strip.empty?
  context_text = SYSTEM_CONTEXT.strip
end

if context_text && !context_text.empty?
  messages << { role: "system", content: context_text }
end

def colorize(pastel, color_name, text, bold: false)
  if bold
    pastel.send(color_name).bold(text)
  else
    pastel.send(color_name, text)
  end
end

def print_header(pastel)
  width = TTY::Screen.width
  separator = "─" * width
  title = "OLLAMA CLI CHAT"

  puts
  puts colorize(pastel, COLORS[:primary], separator, bold: true)
  puts colorize(pastel, COLORS[:primary], title.center(width), bold: true)
  puts colorize(pastel, COLORS[:primary], separator, bold: true)
  puts
end

def print_user_message(text, pastel)
  timestamp = Time.now.strftime("%H:%M:%S")
  prefix = colorize(pastel, COLORS[:success], "You", bold: true)
  timestamp_str = colorize(pastel, COLORS[:dim], "[#{timestamp}]")

  puts "#{prefix} #{timestamp_str}"
  puts colorize(pastel, COLORS[:success], text)
  puts
end

def print_ai_message(text, pastel, streaming: false)
  timestamp = Time.now.strftime("%H:%M:%S")
  width = TTY::Screen.width

  label = streaming ? "Ollama [streaming]" : "Ollama"
  prefix = colorize(pastel, COLORS[:secondary], label, bold: true)
  timestamp_str = colorize(pastel, COLORS[:dim], "[#{timestamp}]")

  puts "#{prefix} #{timestamp_str}"

  # Render markdown with proper width
  markdown = TTY::Markdown.parse(text, width: width - 2, indent: 0)
  puts markdown
  puts
end

def stream_response(user_input, pastel, messages)
  messages << { role: "user", content: user_input }

  request_body = {
    model: MODEL,
    messages: messages,
    stream: true
  }

  timestamp = Time.now.strftime("%H:%M:%S")
  label = "Ollama [streaming]"
  prefix = colorize(pastel, COLORS[:secondary], label, bold: true)
  timestamp_str = colorize(pastel, COLORS[:dim], "[#{timestamp}]")

  puts "#{prefix} #{timestamp_str}"

  full_response = ""
  buffer = +""

  begin
    req = Net::HTTP::Post.new(OLLAMA_STREAM_URL.path)
    req["Content-Type"] = "application/json"
    req.body = request_body.to_json

    Net::HTTP.start(
      OLLAMA_STREAM_URL.hostname,
      OLLAMA_STREAM_URL.port,
      read_timeout: 300,
      open_timeout: 10
    ) do |http|
      http.request(req) do |res|
        raise StandardError, "HTTP #{res.code}: #{res.message}" unless res.is_a?(Net::HTTPSuccess)

        res.read_body do |chunk|
          buffer << chunk

          while (newline_idx = buffer.index("\n"))
            line = buffer.slice!(0, newline_idx + 1).strip
            next if line.empty?

            # Handle SSE framing
            if line.start_with?("data:")
              line = line.sub(/\Adata:\s*/, "").strip
            elsif line.start_with?("event:") || line.start_with?(":")
              next
            end

            next if line.empty? || line == "[DONE]"

            begin
              data = JSON.parse(line)
              delta = data.dig("message", "content")

              if delta && !delta.to_s.empty?
                delta_str = delta.to_s
                full_response += delta_str

                # Print streaming text if in streaming mode
                if DISPLAY_MODE == :streaming
                  print delta_str
                  $stdout.flush
                end
              end
            rescue JSON::ParserError
              # Skip invalid JSON lines
            end
          end
        end
      end
    end

    # Render based on display mode
    if !full_response.empty?
      if DISPLAY_MODE == :markdown
        # Render formatted markdown
        width = TTY::Screen.width
        markdown = TTY::Markdown.parse(full_response, width: width - 2, indent: 0)
        puts markdown
      elsif DISPLAY_MODE == :streaming
        # In streaming mode, text was already printed, just ensure newline
        puts unless full_response.end_with?("\n")
      end
    else
      puts
    end

    puts

    messages << { role: "assistant", content: full_response } unless full_response.empty?
    full_response
  rescue StandardError => e
    puts
    puts
    raise e
  end
end

def show_loading(pastel)
  spinner = TTY::Spinner.new(
    format: :dots,
    message: colorize(pastel, COLORS[:warning], "Processing"),
    success_mark: colorize(pastel, COLORS[:success], "✓"),
    error_mark: colorize(pastel, COLORS[:error], "✗")
  )

  spinner.auto_spin
  yield
  spinner.success(colorize(pastel, COLORS[:success], "Ready"))
rescue StandardError => e
  spinner.error(colorize(pastel, COLORS[:error], "Failed: #{e.message}"))
  raise
end

def print_error(message, pastel)
  prefix = colorize(pastel, COLORS[:error], "Error", bold: true)
  puts "#{prefix}: #{message}"
  puts
end

def print_info(message, pastel)
  info_text = "ℹ #{message}"
  puts pastel.send(COLORS[:info]).dim(info_text)
end

# Main application
system("clear") || system("cls")
print_header(pastel)
mode_info = DISPLAY_MODE == :streaming ? "streaming" : "markdown"
has_context = messages.any? { |m| m["role"] == "system" }
context_info = has_context ? "context: yes" : "context: no"
context_source = SYSTEM_CONTEXT_FILE ? "file: #{File.basename(SYSTEM_CONTEXT_FILE)}" : (SYSTEM_CONTEXT ? "text" : "none")
print_info("Model: #{MODEL} | Mode: #{mode_info} | #{context_info} (#{context_source}) | Commands: '/context <text>', '/context-file <path>', '/show-context'", pastel)
puts

loop do
  # Use simple prompt indicator
  prompt_indicator = colorize(pastel, COLORS[:success], "> ", bold: true)
  user_input = prompt.ask(prompt_indicator) do |q|
    q.modify :strip
  end

  break if user_input.nil? || %w[exit quit].include?(user_input.downcase)

  if user_input.downcase == "clear"
    # Clear conversation but keep system message if present
    system_msg = messages.find { |m| m["role"] == "system" }
    messages.clear
    messages << system_msg if system_msg
    print_info("Conversation history cleared.", pastel)
    puts
    next
  end

  # Handle context command: /context <your context here> or /context-file <path>
  if user_input.downcase.start_with?("/context ")
    context_text = user_input.sub(/^\/context\s+/i, "").strip
    if context_text.empty?
      print_info("Usage: /context <your context or instructions>", pastel)
      puts
      next
    end

    # Update or add system message
    system_msg = messages.find { |m| m["role"] == "system" }
    if system_msg
      system_msg["content"] = context_text
      print_info("System context updated.", pastel)
    else
      messages.unshift({ role: "system", content: context_text })
      print_info("System context added.", pastel)
    end
    puts
    next
  end

  # Handle context file command: /context-file <path>
  if user_input.downcase.start_with?("/context-file ")
    file_path = user_input.sub(/^\/context-file\s+/i, "").strip
    if file_path.empty?
      print_info("Usage: /context-file <path to markdown/text file>", pastel)
      puts
      next
    end

    loaded_context = load_context_from_file(file_path)
    if loaded_context
      # Update or add system message
      system_msg = messages.find { |m| m["role"] == "system" }
      if system_msg
        system_msg["content"] = loaded_context
        print_info("System context loaded from: #{file_path}", pastel)
      else
        messages.unshift({ role: "system", content: loaded_context })
        print_info("System context loaded from: #{file_path}", pastel)
      end
    else
      print_error("Could not load context from file: #{file_path}", pastel)
    end
    puts
    next
  end

  # Show current context: /show-context
  if user_input.downcase == "/show-context"
    system_msg = messages.find { |m| m["role"] == "system" }
    if system_msg
      puts colorize(pastel, COLORS[:info], "Current system context:")
      puts colorize(pastel, COLORS[:dim], system_msg["content"])
    else
      print_info("No system context set.", pastel)
    end
    puts
    next
  end

  next if user_input.empty?

  # Clear the prompt line and print formatted version
  print TTY::Cursor.up
  print TTY::Cursor.clear_line
  print_user_message(user_input, pastel)

  begin
    show_loading(pastel) do
      sleep(0.1) # Brief pause for visual effect
    end

    stream_response(user_input, pastel, messages)
  rescue StandardError => e
    print_error("Connection error: #{e.message}", pastel)
    print_info("Make sure Ollama is running on http://localhost:11434", pastel)
    puts
  end
end

puts
goodbye_text = "👋 Goodbye!"
puts colorize(pastel, COLORS[:info], goodbye_text, bold: true)
puts

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
require "tty-prompt"
require "tty-reader"
require "tty-markdown"
require "tty-spinner"
require "tty-cursor"
require "tty-screen"
require "pastel"
require "time"

# Configuration
MODEL = ENV.fetch("OLLAMA_MODEL", "llama3.2")

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
SYSTEM_CONTEXT_FILE = ENV.fetch("OLLAMA_SYSTEM_FILE", nil) # "/home/nemesis/project/ollama-client/examples/ollama-api.md") # Path to markdown/text file to use as context

# UI Components
pastel = Pastel.new(enabled: true)
reader = TTY::Reader.new

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

# Initialize Ollama client
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = DISPLAY_MODE == :streaming
config.model = MODEL
config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
config.timeout = 60 # Increase timeout for slower models
config.num_ctx = 8192 # Set context window size (increase if needed)

client = Ollama::Client.new(config: config)

# Helper to display available models
def show_available_models(client, pastel)
  models = client.list_models
  if models.empty?
    print_info("No models available locally. Use 'ollama pull <model>' to download models.", pastel)
  else
    puts colorize(pastel, COLORS[:info], "Available models (#{models.length}):", bold: true)
    models.each do |model|
      puts colorize(pastel, COLORS[:dim], "  • #{model}")
    end
  end
rescue StandardError => e
  print_error("Could not fetch models: #{e.message}", pastel)
end

# Load system context
# Priority: SYSTEM_CONTEXT_FILE > SYSTEM_CONTEXT > ENV
context_text = nil
if SYSTEM_CONTEXT_FILE
  loaded_context = load_context_from_file(SYSTEM_CONTEXT_FILE)
  if loaded_context
    # Check if context is too large (rough estimate: ~4 chars per token)
    # For 8K context window, allow ~6000 chars to leave room for conversation
    # For 16K context window, allow ~14000 chars
    max_context_size = config.num_ctx ? (config.num_ctx * 0.75 * 4).to_i : 6000
    if loaded_context.length > max_context_size
      warn "Warning: Context file is very large (#{loaded_context.length} chars). Truncating to #{max_context_size} chars to avoid context size errors."
      context_text = loaded_context[0..max_context_size] + "\n\n[Context truncated due to size limits]"
    else
      context_text = loaded_context
    end
    puts "Loaded context from: #{SYSTEM_CONTEXT_FILE} (#{context_text.length} chars)" if context_text
  end
end

context_text = SYSTEM_CONTEXT.strip if !context_text && SYSTEM_CONTEXT && !SYSTEM_CONTEXT.strip.empty?

# Create streaming observer for display
streaming_observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    if DISPLAY_MODE == :streaming
      print event.text
      $stdout.flush
    end
  when :final
    # Ensure newline after streaming completes
    if DISPLAY_MODE == :streaming
      puts # Add newline after streaming
    end
  end
end

# Create chat session with system context
chat = Ollama::ChatSession.new(
  client,
  system: context_text,
  stream: DISPLAY_MODE == :streaming ? streaming_observer : nil
)

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

def get_response(user_input, pastel, chat, model_name)
  timestamp = Time.now.strftime("%H:%M:%S")
  label = DISPLAY_MODE == :streaming ? "Ollama [streaming]" : "Ollama"
  prefix = colorize(pastel, COLORS[:secondary], label, bold: true)
  timestamp_str = colorize(pastel, COLORS[:dim], "[#{timestamp}]")
  model_str = colorize(pastel, COLORS[:dim], "[#{model_name}]")

  # Print header, but in streaming mode, print on same line to avoid cursor issues
  if DISPLAY_MODE == :streaming
    print "#{prefix} #{model_str} #{timestamp_str} "
    $stdout.flush
  else
    puts "#{prefix} #{model_str} #{timestamp_str}"
  end

  begin
    # Show loading indicator for markdown mode
    if DISPLAY_MODE == :markdown
      print colorize(pastel, COLORS[:dim], "Thinking... ", bold: false)
      $stdout.flush
    end

    # Use ChatSession to get response with timeout handling
    response = nil
    begin
      response = chat.say(user_input)
    rescue Ollama::TimeoutError => e
      raise StandardError, "Request timed out: #{e.message}. The model may be slow or unresponsive."
    end

    # Clear loading indicator
    if DISPLAY_MODE == :markdown
      print TTY::Cursor.clear_line
      print TTY::Cursor.column(0)
    end

    # Render with markdown formatting if in markdown mode
    if DISPLAY_MODE == :markdown && !response.empty?
      width = TTY::Screen.width
      markdown = TTY::Markdown.parse(response, width: width - 2, indent: 0)
      puts markdown
    elsif DISPLAY_MODE == :streaming
      # In streaming mode, text was already printed via observer
      # If response is empty, something went wrong - show what we got
      if response.nil? || response.empty?
        print_error("Empty response received from model. Check if model is loaded correctly.", pastel)
        print_info("Model: #{model_name}, Response length: #{response&.length || 0}", pastel)
      end
      # Note: In streaming mode, text is printed via observer, so we don't need to print again
    end

    puts
    response
  rescue Ollama::ChatNotAllowedError => e
    raise StandardError, "Chat not allowed: #{e.message}. Make sure config.allow_chat = true"
  rescue Ollama::Error => e
    raise StandardError, "Ollama error: #{e.message}"
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

# Display configuration info
current_model = config.model || MODEL
mode_info = DISPLAY_MODE == :streaming ? "streaming" : "markdown"
has_context = chat.messages.any? { |m| m["role"] == "system" }
context_info = has_context ? "yes" : "no"
context_source = if SYSTEM_CONTEXT_FILE && has_context
                   "file: #{File.basename(SYSTEM_CONTEXT_FILE)}"
                 elsif SYSTEM_CONTEXT && has_context
                   "text"
                 else
                   "none"
                 end

print_info("URL: #{config.base_url} | Model: #{current_model} | Mode: #{mode_info} | Context: #{context_info} (#{context_source})", pastel)
print_info("Commands: '/models', '/paste', '/context <text>', '/context-file <path>', '/show-context', 'clear', 'exit'", pastel)
puts

loop do
  # Use TTY::Reader for multiline input support
  # For paste support, we need to collect ALL lines before processing
  prompt_indicator = colorize(pastel, COLORS[:success], "> ", bold: true)

  # Read first line
  first_line = reader.read_line(prompt_indicator)
  break if first_line.nil? # EOF (Ctrl+D)

  first_line = first_line.strip
  break if first_line.empty? || %w[exit quit].include?(first_line.downcase)

  # Commands are always single line - process immediately
  if first_line.start_with?("/")
    user_input = first_line
  else
    # For regular input, collect all lines
    # When pasting multiline text, all lines come through read_line quickly
    # We collect them all, then process once
    lines = [first_line]
    continuation_prompt = colorize(pastel, COLORS[:dim], "  ", bold: false)

    # Keep reading lines until we get an empty line
    # This ensures we collect all pasted lines before processing
    loop do
      line = reader.read_line(continuation_prompt)
      break if line.nil? # EOF (Ctrl+D)

      stripped = line.strip
      # Empty line signals end of input
      if stripped.empty?
        # We have content, empty line means "done"
        break
      end

      # Add non-empty line to collection
      lines << line
    end

    # Join all collected lines into one input
    user_input = lines.join("\n").strip
  end

  # Only process if we have input
  break if user_input.nil? || user_input.empty?

  if user_input.downcase == "clear"
    # Clear conversation history (ChatSession preserves system message)
    chat.clear
    print_info("Conversation history cleared.", pastel)
    puts
    next
  end

  # Handle context command: /context <your context here> or /context-file <path>
  if user_input.downcase.start_with?("/context ")
    context_text = user_input.sub(%r{^/context\s+}i, "").strip
    if context_text.empty?
      print_info("Usage: /context <your context or instructions>", pastel)
      puts
      next
    end

    # Update system message in chat session
    # Note: ChatSession doesn't expose direct system message update,
    # so we need to recreate the session or work with messages directly
    system_msg = chat.messages.find { |m| m["role"] == "system" }
    if system_msg
      system_msg["content"] = context_text
      print_info("System context updated.", pastel)
    else
      chat.messages.unshift({ "role" => "system", "content" => context_text })
      print_info("System context added.", pastel)
    end
    puts
    next
  end

  # Handle context file command: /context-file <path>
  if user_input.downcase.start_with?("/context-file ")
    file_path = user_input.sub(%r{^/context-file\s+}i, "").strip
    if file_path.empty?
      print_info("Usage: /context-file <path to markdown/text file>", pastel)
      puts
      next
    end

    loaded_context = load_context_from_file(file_path)
    if loaded_context
      # Update system message in chat session
      system_msg = chat.messages.find { |m| m["role"] == "system" }
      if system_msg
        system_msg["content"] = loaded_context
        print_info("System context loaded from: #{file_path}", pastel)
      else
        chat.messages.unshift({ "role" => "system", "content" => loaded_context })
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
    system_msg = chat.messages.find { |m| m["role"] == "system" }
    if system_msg
      puts colorize(pastel, COLORS[:info], "Current system context:")
      puts colorize(pastel, COLORS[:dim], system_msg["content"])
    else
      print_info("No system context set.", pastel)
    end
    puts
    next
  end

  # List available models: /models or /list-models
  if user_input.downcase == "/models" || user_input.downcase == "/list-models"
    show_available_models(client, pastel)
    puts
    next
  end

  # Paste mode: /paste - allows multiline paste, ends with Ctrl+D or empty line
  if user_input.downcase == "/paste"
    print_info("Paste mode: Paste your multiline text, then press Ctrl+D or Enter on empty line to finish", pastel)
    paste_lines = []
    paste_prompt = colorize(pastel, COLORS[:dim], "paste> ", bold: false)

    loop do
      line = reader.read_line(paste_prompt)
      break if line.nil? # Ctrl+D

      stripped = line.strip
      # Empty line ends paste mode
      break if stripped.empty? && !paste_lines.empty?
      next if stripped.empty? && paste_lines.empty?

      paste_lines << line
    end

    user_input = paste_lines.join("\n").strip
    if user_input.empty?
      print_info("No input pasted.", pastel)
      puts
      next
    end
  end

  next if user_input.empty?

  # Clear the prompt line and print formatted version
  print TTY::Cursor.up
  print TTY::Cursor.clear_line
  print_user_message(user_input, pastel)

  begin
    current_model = config.model || MODEL
    get_response(user_input, pastel, chat, current_model)
  rescue StandardError => e
    print_error("Connection error: #{e.message}", pastel)
    base_url = config.base_url || ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    print_info("Make sure Ollama is running on #{base_url}", pastel)
    puts
  end
end

puts
goodbye_text = "👋 Goodbye!"
puts colorize(pastel, COLORS[:info], goodbye_text, bold: true)
puts

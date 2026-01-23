#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using ChatSession for human-facing chat interfaces
#
# This demonstrates the recommended way to build interactive chat UIs
# with streaming and conversation history management.

require_relative "../lib/ollama_client"

# Configure client with chat enabled
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true

client = Ollama::Client.new(config: config)

# Create streaming observer for real-time token display
observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    print event.text
    $stdout.flush
  when :tool_call_detected
    puts "\n[Tool call: #{event.name}]"
  when :final
    puts "\n"
  end
end

# Create chat session with system message
chat = Ollama::ChatSession.new(
  client,
  system: "You are a helpful Ruby programming assistant. Be concise and practical.",
  stream: observer
)

puts "=== ChatSession Example ===\n\n"
puts "Type messages to chat. Type 'quit' to exit, 'clear' to reset history.\n\n"

loop do
  print "You: "
  input = $stdin.gets&.chomp

  break if input.nil? || input.downcase == "quit"

  if input.downcase == "clear"
    chat.clear
    puts "Conversation history cleared.\n\n"
    next
  end

  next if input.empty?

  print "Assistant: "
  begin
    response = chat.say(input)
    # Response is already printed via streaming, just ensure spacing
    puts "" if response.empty?
  rescue Ollama::ChatNotAllowedError => e
    puts "\n❌ Error: #{e.message}"
    puts "Make sure config.allow_chat = true"
  rescue Ollama::Error => e
    puts "\n❌ Error: #{e.message}"
  end
end

puts "\nGoodbye!"

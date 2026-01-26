#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Basic /chat usage
# Demonstrates client transport layer - stateful message handling

require_relative "../lib/ollama_client"

client = Ollama::Client.new

# Simple chat message
response = client.chat_raw(
  messages: [{ role: "user", content: "Say hello." }],
  allow_chat: true
)

puts "Response: #{response.message.content}"
puts "Role: #{response.message.role}"

# Multi-turn conversation
messages = [
  { role: "user", content: "What is Ruby?" }
]

response1 = client.chat_raw(messages: messages, allow_chat: true)
puts "\nFirst response: #{response1.message.content}"

# Continue conversation
messages << { role: "assistant", content: response1.message.content }
messages << { role: "user", content: "Tell me more about its use cases" }

response2 = client.chat_raw(messages: messages, allow_chat: true)
puts "\nSecond response: #{response2.message.content}"

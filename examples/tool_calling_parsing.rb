#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Tool-call parsing (no execution)
# Demonstrates client transport layer - tool-call detection and extraction
# NOTE: This example does NOT execute tools. It only parses tool calls from the LLM response.

require "json"
require_relative "../lib/ollama_client"

client = Ollama::Client.new

# Define tool using Tool classes
tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_weather",
    description: "Get weather for a location",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        location: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The city name"
        )
      },
      required: %w[location]
    )
  )
)

# Request tool call from LLM
response = client.chat_raw(
  messages: [{ role: "user", content: "What's the weather in Paris?" }],
  tools: tool,
  allow_chat: true
)

# Parse tool calls (but do NOT execute)
tool_calls = response.message&.tool_calls

if tool_calls && !tool_calls.empty?
  puts "Tool calls detected:"
  tool_calls.each do |call|
    # Access via method (if available)
    name = call.respond_to?(:name) ? call.name : call["function"]["name"]
    args = call.respond_to?(:arguments) ? call.arguments : JSON.parse(call["function"]["arguments"])

    puts "  Tool: #{name}"
    puts "  Arguments: #{args.inspect}"
    puts "  (Tool execution would happen here in your agent code)"
  end
else
  puts "No tool calls in response"
  puts "Response: #{response.message&.content}"
end

# Alternative: Access via hash
# tool_calls = response.to_h.dig("message", "tool_calls")

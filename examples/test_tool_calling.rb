#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script to verify Tool calling with chat_raw() and chat()
# This demonstrates the new structured Tool classes and Response wrapper

require_relative "lib/ollama_client"

puts "\n=== TOOL CALLING TEST ===\n"

client = Ollama::Client.new

# Define a simple tool using structured Tool classes
weather_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_weather",
    description: "Get the current weather for a location",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        location: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The city name, e.g. Paris, London"
        ),
        unit: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Temperature unit",
          enum: %w[celsius fahrenheit]
        )
      },
      required: %w[location]
    )
  )
)

# Test 1: Using chat_raw() to access tool_calls
puts "\n--- Test 1: chat_raw() with Tool object ---"
puts "Sending request with tool definition..."

begin
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("What's the weather in Paris? Use celsius.")],
    tools: weather_tool,
    allow_chat: true
  )

  puts "\n✅ Response received"
  puts "Response class: #{response.class.name}"

  # Method access (like ollama-ruby)
  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "\n✅ Tool calls detected (via method access):"
    tool_calls.each do |call|
      puts "  - Tool: #{call.name}"
      puts "    Arguments: #{call.arguments}"
      puts "    ID: #{call.id}"
    end
  else
    puts "\n⚠️  No tool calls detected"
    puts "Content: #{response.message&.content}"
  end

  # Hash access (backward compatible)
  tool_calls_hash = response.to_h.dig("message", "tool_calls")
  if tool_calls_hash && !tool_calls_hash.empty?
    puts "\n✅ Tool calls also accessible via hash:"
    puts "  Count: #{tool_calls_hash.length}"
  end
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
  puts "\n   Note: This is expected if Ollama server is not running"
  puts "   The important part is that the code structure is correct"
end

# Test 2: Using chat() with tools (returns content only)
puts "\n--- Test 2: chat() with Tool object ---"
puts "Sending request with tool definition..."

begin
  content = client.chat(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("What's the weather in London?")],
    tools: weather_tool,
    allow_chat: true
  )

  puts "\n✅ Response received"
  if content.empty?
    puts "⚠️  Content is empty (model returned only tool_calls)"
    puts "   Use chat_raw() to access tool_calls"
  else
    puts "Content: #{content}"
  end
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
end

# Test 3: Multiple tools (array)
puts "\n--- Test 3: Multiple tools (array) ---"

time_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_time",
    description: "Get the current time",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        timezone: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Timezone (default: UTC)",
          enum: %w[UTC EST PST]
        )
      },
      required: []
    )
  )
)

begin
  response = client.chat_raw(
    model: "llama3.1:8b",
    messages: [Ollama::Agent::Messages.user("What time is it? Use the get_time tool.")],
    tools: [weather_tool, time_tool], # Array of Tool objects
    allow_chat: true
  )

  puts "\n✅ Response received"
  tool_calls = response.message&.tool_calls
  if tool_calls && !tool_calls.empty?
    puts "\n✅ Tool calls detected:"
    tool_calls.each do |call|
      puts "  - #{call.name}: #{call.arguments}"
    end
  else
    puts "\n⚠️  No tool calls detected"
  end
rescue Ollama::Error => e
  puts "\n❌ Error: #{e.class.name}"
  puts "   Message: #{e.message}"
end

# Test 4: Verify Tool object structure
puts "\n--- Test 4: Tool object structure ---"
puts "Weather tool:"
puts "  Type: #{weather_tool.type}"
puts "  Function name: #{weather_tool.function.name}"
puts "  Function description: #{weather_tool.function.description}"
puts "  Parameters type: #{weather_tool.function.parameters.type}"
puts "  Required params: #{weather_tool.function.parameters.required}"

puts "\nTool.to_h (for API):"
puts weather_tool.to_h.inspect

puts "\n=== DONE ===\n"

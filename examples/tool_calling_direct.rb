#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Direct Tool Calling (matching ollama-ruby pattern)
# Demonstrates using Tool objects directly with chat()

require "json"
require_relative "../lib/ollama_client"
require_relative "../lib/ollama/agent/messages"

puts "\n=== DIRECT TOOL CALLING EXAMPLE ===\n"

client = Ollama::Client.new

# Define tool using Tool classes (matching ollama-ruby pattern)
tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_current_weather",
    description: "Get the current weather for a location",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        location: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The location to get the weather for, e.g. San Francisco, CA"
        ),
        temperature_unit: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The unit to return the temperature in, either 'celsius' or 'fahrenheit'",
          enum: %w[celsius fahrenheit]
        )
      },
      required: %w[location temperature_unit]
    )
  )
)

# Create message
def message(location)
  Ollama::Agent::Messages.user("What is the weather today in #{location}?")
end

puts "\n--- Using chat() to access tool_calls ---"

# chat() always returns a full Ollama::Response — message.tool_calls is
# populated whenever the model calls a tool. tools: takes an array.
response = client.chat(
  model: "llama3.1:8b",
  messages: [message("The City of Love")],
  tools: [tool]
)

# Access tool_calls from response (using method access like ollama-ruby)
tool_calls = response.message&.tool_calls
if tool_calls && !tool_calls.empty?
  puts "\nTool calls detected:"
  tool_calls.each do |call|
    name = call.name
    args = call.arguments
    puts "  - #{name}: #{args}"
  end
else
  puts "\nNo tool calls in response"
  puts "Response: #{response.message&.content}"
end

# You can also use hash access if preferred:
# tool_calls = response.to_h.dig("message", "tool_calls")

puts "\n--- Multiple tools (array) ---"

# You can also pass an array of tools
tool2 = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_time",
    description: "Get the current time",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {},
      required: []
    )
  )
)

response2 = client.chat(
  model: "llama3.1:8b",
  messages: [Ollama::Agent::Messages.user("What time is it? Use the get_time tool.")],
  tools: [tool, tool2] # Array of Tool objects
)

tool_calls2 = response2.message&.tool_calls
if tool_calls2 && !tool_calls2.empty?
  puts "\nTool calls from multiple tools:"
  tool_calls2.each do |call|
    puts "  - #{call.name}"
  end
end

puts "\n=== DONE ===\n"

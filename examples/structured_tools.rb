#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using Structured Tool Definitions
# Demonstrates explicit Tool classes for type-safe tool schemas

require "json"
require_relative "../lib/ollama_client"

puts "\n=== STRUCTURED TOOLS EXAMPLE ===\n"

client = Ollama::Client.new

# Define tools with explicit schemas using Tool classes
location_property = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "The city and state, e.g. San Francisco, CA"
)

unit_property = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "The unit to return temperature in",
  enum: %w[celsius fahrenheit]
)

weather_parameters = Ollama::Tool::Function::Parameters.new(
  type: "object",
  properties: {
    location: location_property,
    unit: unit_property
  },
  required: %w[location unit]
)

weather_function = Ollama::Tool::Function.new(
  name: "get_current_weather",
  description: "Get the current weather for a location",
  parameters: weather_parameters
)

weather_tool = Ollama::Tool.new(
  type: "function",
  function: weather_function
)

# Define the actual callable
weather_callable = lambda do |location:, unit:|
  {
    location: location,
    unit: unit,
    temperature: unit == "celsius" ? "22" : "72",
    condition: "sunny"
  }
end

# Use structured tool definition with callable
tools = {
  "get_current_weather" => {
    tool: weather_tool,
    callable: weather_callable
  }
}

# Alternative: Simple callable (auto-inferred schema)
# This still works for backward compatibility - just pass the callable directly
simple_tools = {
  "get_time" => lambda do |timezone: "UTC"|
    { timezone: timezone, time: Time.now.utc.iso8601 }
  end
}

# Combine both approaches
# Simple callables can be passed directly (auto-inferred)
all_tools = tools.merge(simple_tools)

executor = Ollama::Agent::Executor.new(client, tools: all_tools)

begin
  answer = executor.run(
    system: "You are a helpful assistant. Use tools when needed.",
    user: "What's the weather in Paris, France? Use celsius."
  )

  puts "\nAnswer: #{answer}"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end

puts "\n=== DONE ===\n"

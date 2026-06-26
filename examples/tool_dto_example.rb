#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Tool DTO (Data Transfer Object) functionality
# Demonstrates serialization, deserialization, and equality

require "json"
require_relative "../lib/ollama_client"

puts "\n=== TOOL DTO EXAMPLE ===\n"

# Create a tool definition
location_prop = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "The city name"
)

unit_prop = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "Temperature unit",
  enum: %w[celsius fahrenheit]
)

params = Ollama::Tool::Function::Parameters.new(
  type: "object",
  properties: {
    location: location_prop,
    unit: unit_prop
  },
  required: %w[location unit]
)

function = Ollama::Tool::Function.new(
  name: "get_weather",
  description: "Get weather for a location",
  parameters: params
)

tool = Ollama::Tool.new(type: "function", function: function)

# 1. Serialize to JSON
puts "\n--- Serialization ---"
json_str = tool.to_json
puts "JSON: #{json_str}"

# 2. Deserialize from hash
puts "\n--- Deserialization ---"
hash = JSON.parse(json_str)
deserialized_tool = Ollama::Tool.from_hash(hash)
puts "Deserialized tool name: #{deserialized_tool.function.name}"

# 3. Equality comparison
puts "\n--- Equality ---"
puts "Original == Deserialized: #{tool == deserialized_tool}"

# 4. Nested deserialization
puts "\n--- Nested Deserialization ---"
function_hash = {
  "name" => "get_time",
  "description" => "Get current time",
  "parameters" => {
    "type" => "object",
    "properties" => {
      "timezone" => {
        "type" => "string",
        "description" => "Timezone (e.g., UTC, EST)"
      }
    },
    "required" => []
  }
}

deserialized_function = Ollama::Tool::Function.from_hash(function_hash)
puts "Deserialized function: #{deserialized_function.name}"
puts "Parameters type: #{deserialized_function.parameters.type}"

# 5. Property deserialization
puts "\n--- Property Deserialization ---"
prop_hash = {
  "type" => "string",
  "description" => "City name",
  "enum" => %w[paris london tokyo]
}

deserialized_prop = Ollama::Tool::Function::Parameters::Property.from_hash(prop_hash)
puts "Property type: #{deserialized_prop.type}"
puts "Property enum: #{deserialized_prop.enum.inspect}"

# 6. Empty check
puts "\n--- Empty Check ---"
empty_params = Ollama::Tool::Function::Parameters.new(type: "object", properties: {}, required: [])
puts "Empty params? #{empty_params.empty?}"

puts "\n=== DONE ===\n"

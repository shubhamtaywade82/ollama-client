#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Basic /generate usage with schema validation
# Demonstrates client transport layer - stateless, deterministic JSON output

require_relative "../lib/ollama_client"

client = Ollama::Client.new

# Define schema for structured output
schema = {
  "type" => "object",
  "required" => ["status"],
  "properties" => {
    "status" => { "type" => "string" }
  }
}

# Generate structured JSON response
result = client.generate(
  prompt: "Output a JSON object with a single key 'status' and value 'ok'.",
  schema: schema
)

puts "Result: #{result.inspect}"
puts "Status: #{result['status']}" # => "ok"

# The result is guaranteed to match your schema!

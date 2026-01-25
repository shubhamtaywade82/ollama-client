#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Ollama structured outputs using chat API
# This matches the JavaScript example from the Ollama documentation

# Load .env file if available (overload to ensure .env takes precedence over shell env)
begin
  require "dotenv"
  Dotenv.overload
rescue LoadError
  # dotenv not available, skip
end

require "json"
require_relative "../lib/ollama_client"

def run(model)
  # Define the JSON schema for friend info
  friend_info_schema = {
    "type" => "object",
    "required" => %w[name age is_available],
    "properties" => {
      "name" => {
        "type" => "string",
        "description" => "The name of the friend"
      },
      "age" => {
        "type" => "integer",
        "description" => "The age of the friend"
      },
      "is_available" => {
        "type" => "boolean",
        "description" => "Whether the friend is available"
      }
    }
  }

  # Define the schema for friend list
  friend_list_schema = {
    "type" => "object",
    "required" => ["friends"],
    "properties" => {
      "friends" => {
        "type" => "array",
        "description" => "An array of friends",
        "items" => friend_info_schema
      }
    }
  }
  config = Ollama::Config.new
  config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", config.model)
  client = Ollama::Client.new(config: config)

  messages = [{
    role: "user",
    content: "I have two friends. The first is Ollama 22 years old busy saving the world, " \
             "and the second is Alonso 23 years old and wants to hang out. " \
             "Return a list of friends in JSON format"
  }]

  response = client.chat(
    model: model,
    messages: messages,
    format: friend_list_schema,
    allow_chat: true,
    options: {
      temperature: 0 # Make responses more deterministic
    }
  )

  # Parse and validate the response (already validated by client, but showing usage)
  begin
    friends_response = response # Already parsed and validated
    puts JSON.pretty_generate(friends_response)
  rescue Ollama::SchemaViolationError => e
    puts "Generated invalid response: #{e.message}"
  end
end

# Run with the same model as the JavaScript example
run("llama3.1:8b")

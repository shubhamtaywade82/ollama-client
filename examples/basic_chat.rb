#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic chat completion with Ollama
require "ollama_client"

client = Ollama::Client.new
response = client.chat(model: "llama3.1:8b", messages: [{ role: "user", content: "Hello, how are you?" }])
puts response

#!/usr/bin/env ruby
# frozen_string_literal: true

# Streaming chat completion
require "ollama_client"

client = Ollama::Client.new
client.chat(model: "llama3.1:8b", messages: [{ role: "user", content: "Count from 1 to 5" }], stream: true) do |chunk|
  print chunk.dig("message", "content")
  $stdout.flush
end
puts

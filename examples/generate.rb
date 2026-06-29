#!/usr/bin/env ruby
# frozen_string_literal: true

# Single completion (generate endpoint)
require "ollama_client"

client = Ollama::Client.new
response = client.generate(prompt: "Explain quantum computing in one sentence", model: "llama3.1:8b")
puts response

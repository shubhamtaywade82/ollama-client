#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate embeddings
require "ollama_client"

client = Ollama::Client.new
response = client.embeddings.embed(model: "nomic-embed-text", input: "Hello, world!")
puts "Embedding dimension: #{response.length}"
puts "First 5 values: #{response.first(5)}"

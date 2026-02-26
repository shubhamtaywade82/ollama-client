# frozen_string_literal: true

require_relative "lib/ollama_client"
require "json"

client = Ollama::Client.new
models = client.list_models

puts "Model Name | Tools | Thinking | Vision | Embeddings"
puts "-" * 60

models.each do |m|
  c = m["capabilities"]
  name = m["name"].ljust(30)
  tools = c["tools"] ? "✅" : "❌"
  think = c["thinking"] ? "✅" : "❌"
  vis = c["vision"] ? "✅" : "❌"
  emb = c["embeddings"] ? "✅" : "❌"
  puts "#{name} | #{tools} | #{think} | #{vis} | #{emb}"
end

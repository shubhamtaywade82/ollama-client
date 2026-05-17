# frozen_string_literal: true

require_relative "../lib/ollama-client"
require "json"

# This script tests the connection between ollama-client gem 
# and the llama.cpp GPU server running via Docker.

puts "🚀 Initializing Llama.cpp GPU Test..."

# 1. Configure the client for llama.cpp (OpenAI Provider)
config = Ollama::Config.new
config.base_url = "http://localhost:8080/v1"
config.provider = :openai
config.model = "google_gemma-4-E4B-it-Q4_K_M.gguf" # Must match .env
config.timeout = 60

client = Ollama::Client.new(config: config)

# 2. Simple Chat Test
puts "\n💬 Testing Chat Completion..."
begin
  response = client.chat(
    messages: [
      { role: "system", content: "You are a helpful assistant running on a high-performance RTX 4060 GPU." },
      { role: "user", content: "Confirm your model name and if you can feel the GPU power!" }
    ],
    options: { temperature: 0.7 }
  )

  puts "✅ Response received from #{response.model}:"
  puts "----------------------------------------"
  puts response.message.content
  puts "----------------------------------------"
  puts "Usage: #{response.usage.inspect}" if response.usage
rescue StandardError => e
  puts "❌ Error during chat: #{e.message}"
  puts "Note: Ensure the llama-server-gpu container is running and the model is fully downloaded."
end

# 3. JSON Mode Test (if supported by your provider update)
puts "\nSchema Testing (JSON Mode)..."
begin
  json_response = client.chat(
    messages: [{ role: "user", content: "Return a JSON object with 'status': 'working' and 'engine': 'llama.cpp'" }],
    format: "json"
  )
  puts "✅ JSON Response:"
  puts JSON.pretty_generate(JSON.parse(json_response.message.content))
rescue StandardError => e
  puts "⚠️ JSON mode test skipped or failed: #{e.message}"
end

puts "\n🏁 Test finished."

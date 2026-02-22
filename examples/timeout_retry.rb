# frozen_string_literal: true

require "ollama_client"

# In production applications, large models or long context windows
# can cause initial requests to timeout (Net::ReadTimeout).
#
# `ollama-client` handles this gracefully via exponential backoff.
# Example:
#   Attempt 1 fails -> sleep 2s
#   Attempt 2 fails -> sleep 4s
#   Attempt 3 fails -> sleep 8s -> raise RetryExhaustedError if max limit reached
#
# This explicitly prevents overwhelming the server or queuing up too many requests.

client = Ollama::Client.new(
  config: Ollama::Config.new.tap do |c|
    c.model = "llama3.2"
    c.timeout = 5           # A very aggressive timeout
    c.retries = 3           # Let it retry several times
    c.strict_json = true
  end
)

begin
  puts "Sending a huge generation request with a tiny timeout..."
  puts "Watch the logs (or the time elapsed) as exponential backoff activates."

  result = client.generate(
    prompt: "Write a complete 100-page book about cats.",
    return_meta: true       # Returns { data: ..., meta: { attempts: ...} }
  )

  puts "\nSUCCESS on attempt #{result['meta']['attempts']}!"
  puts "Data: #{result['data'][0..50]}..."
rescue Ollama::RetryExhaustedError => e
  # If the server is just too slow, we catch the final Exhausted error.
  puts "We gracefully gave up after #{client.instance_variable_get(:@config).retries} retries."
  puts "Error: #{e.message}"
end

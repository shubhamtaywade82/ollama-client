# frozen_string_literal: true

require "ollama_client"

# In strict mode, if your LLM model returns markdown formatting like:
# ```json
# { "action": "search" }
# ```
# instead of raw JSON, `ollama-client` handles it automatically by triggering
# a repair prompt in the retry loop.

client = Ollama::Client.new(
  config: Ollama::Config.new.tap do |c|
    c.model = "llama3.1:8b"
    c.timeout = 15
    c.retries = 2
    c.strict_json = true # <-- This enables validation & automatic repair!
  end
)

schema = {
  "type" => "object",
  "required" => ["greeting"],
  "properties" => {
    "greeting" => { "type" => "string" }
  }
}

begin
  puts "Sending request. If the model fails the JSON schema, ollama-client will fix it..."

  result = client.generate(
    prompt: "Say hi and don't output JSON, output a paragraph of text instead. (I am challenging you).",
    schema: schema
  )

  puts "\nSUCCESS! Final output:"
  puts result.inspect
rescue Ollama::RetryExhaustedError => e
  # If it failed 2 times, the error is cleanly bubbled up.
  puts "Could not get valid JSON from the model after multiple attempts: #{e.message}"
end

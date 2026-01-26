# Quick Start: Copy-Paste Examples

All examples below are **complete and copy-pasteable** - no missing constants or undefined variables.

## Basic Client Setup

```ruby
require "ollama_client"

# Simplest client (uses defaults)
client = Ollama::Client.new

# Or with custom config
config = Ollama::Config.new
config.model = ENV["OLLAMA_MODEL"] || "llama3.1:8b"
config.base_url = ENV["OLLAMA_BASE_URL"] || "http://localhost:11434"
client = Ollama::Client.new(config: config)
```

## Generate with Schema (Structured Output)

```ruby
require "ollama_client"

client = Ollama::Client.new

DECISION_SCHEMA = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["search", "calculate", "finish"]
    },
    "reasoning" => {
      "type" => "string"
    }
  }
}

result = client.generate(
  prompt: "Analyze the situation and decide next action.",
  schema: DECISION_SCHEMA
)

puts result["action"]      # => "search"
puts result["reasoning"]    # => "User needs data..."
```

## Generate Plain Text

```ruby
require "ollama_client"

client = Ollama::Client.new

response = client.generate(
  prompt: "Explain Ruby blocks in one sentence.",
  allow_plain_text: true
)

puts response  # => Plain text/markdown String
```

## Planner with Persona

```ruby
require "ollama_client"

client = Ollama::Client.new

planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

DECISION_SCHEMA = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["refactor", "test", "document", "defer"]
    },
    "reasoning" => {
      "type" => "string"
    }
  }
}

plan = planner.run(
  prompt: "Design a caching layer for a high-traffic API.",
  schema: DECISION_SCHEMA
)

puts plan["action"]      # => "refactor" (or one of the enum values)
puts plan["reasoning"]    # => Explanation string
```

## Executor with Tools

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define tools (copy-paste ready)
tools = {
  "get_price" => ->(symbol:) { { symbol: symbol, price: 24500.50, volume: 1_000_000 } },
  "get_indicators" => ->(symbol:) { { symbol: symbol, rsi: 65.5, macd: 1.2 } }
}

executor = Ollama::Agent::Executor.new(client, tools: tools)

answer = executor.run(
  system: Ollama::Personas.get(:trading, variant: :agent),
  user: "Analyze NIFTY. Get current price and technical indicators."
)

puts answer
```

## ChatSession (Human-Facing Chat)

```ruby
require "ollama_client"

config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true

client = Ollama::Client.new(config: config)

observer = Ollama::StreamingObserver.new do |event|
  print event.text if event.type == :token
  puts "\n" if event.type == :final
end

chat = Ollama::ChatSession.new(
  client,
  system: Ollama::Personas.get(:architect, variant: :chat),
  stream: observer
)

chat.say("How should I structure a multi-agent system?")
```

## Complete Working Example

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "ollama_client"

# Step 1: Create client
client = Ollama::Client.new

# Step 2: Define schema
DECISION_SCHEMA = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["refactor", "test", "document", "defer"]
    },
    "reasoning" => {
      "type" => "string"
    }
  }
}

# Step 3: Create planner with persona
planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

# Step 4: Use planner
begin
  plan = planner.run(
    prompt: "Design a caching layer for a high-traffic API.",
    schema: DECISION_SCHEMA
  )
  
  puts "✅ Success!"
  puts "Action: #{plan['action']}"
  puts "Reasoning: #{plan['reasoning']}"
rescue Ollama::Error => e
  puts "❌ Error: #{e.message}"
end
```

All examples above are **complete and ready to copy-paste**!

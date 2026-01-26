# Getting Started: Creating an Ollama Client

This guide shows you step-by-step how to create a client object to use all features of `ollama-client`.

## Step 1: Install and Require the Gem

### Option A: Using Bundler (Recommended)

Add to your `Gemfile`:
```ruby
gem "ollama-client"
```

Then run:
```bash
bundle install
```

### Option B: Install Directly

```bash
gem install ollama-client
```

### Step 1b: Require in Your Code

```ruby
require "ollama_client"
```

The `.env` file is automatically loaded when you require the gem (if dotenv is available).

---

## Step 2: Create a Client Object

You have several options depending on your needs:

### Option A: Basic Client (Uses Defaults)

```ruby
require "ollama_client"

# Simplest way - uses default configuration
client = Ollama::Client.new

# Defaults:
# - base_url: "http://localhost:11434"
# - model: "llama3.1:8b"
# - timeout: 20 seconds
# - retries: 2
# - temperature: 0.2
# - allow_chat: false
# - streaming_enabled: false
```

### Option B: Client with Custom Configuration

```ruby
require "ollama_client"

# Create config object
config = Ollama::Config.new

# Customize settings
config.base_url = "http://localhost:11434"  # or your Ollama server URL
config.model = "qwen2.5:14b"                # or your preferred model
config.temperature = 0.1                    # Lower = more deterministic
config.timeout = 60                         # Increase for complex schemas
config.retries = 3                          # Number of retry attempts
config.allow_chat = true                    # Enable chat API (if needed)
config.streaming_enabled = true             # Enable streaming (if needed)

# Create client with custom config
client = Ollama::Client.new(config: config)
```

### Option C: Client from Environment Variables

The gem automatically loads `.env` file. You can set these environment variables:

```bash
# In your .env file or shell environment
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:14b
OLLAMA_TEMPERATURE=0.1
```

Then in your code:

```ruby
require "ollama_client"

# Create config and read from environment
config = Ollama::Config.new
config.base_url = ENV["OLLAMA_BASE_URL"] if ENV["OLLAMA_BASE_URL"]
config.model = ENV["OLLAMA_MODEL"] if ENV["OLLAMA_MODEL"]
config.temperature = ENV["OLLAMA_TEMPERATURE"].to_f if ENV["OLLAMA_TEMPERATURE"]

client = Ollama::Client.new(config: config)
```

### Option D: Client from JSON Config File

Create a `config.json` file:

```json
{
  "base_url": "http://localhost:11434",
  "model": "llama3.1:8b",
  "timeout": 30,
  "retries": 3,
  "temperature": 0.2,
  "top_p": 0.9,
  "num_ctx": 8192
}
```

Then load it:

```ruby
require "ollama_client"

config = Ollama::Config.load_from_json("config.json")
client = Ollama::Client.new(config: config)
```

---

## Step 3: Verify Your Client Works

Test that your client can connect:

```ruby
require "ollama_client"

client = Ollama::Client.new

# List available models (verifies connection)
begin
  models = client.list_models
  puts "✅ Connected! Available models: #{models.map { |m| m['name'] }.join(', ')}"
rescue Ollama::Error => e
  puts "❌ Connection failed: #{e.message}"
  puts "   Make sure Ollama server is running at #{client.instance_variable_get(:@config).base_url}"
end
```

---

## Step 4: Use Client Features

Once you have a client object, you can use all features:

### 4.1: Generate (Structured Outputs) - Recommended for Agents

```ruby
client = Ollama::Client.new

schema = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "calculate", "finish"] },
    "reasoning" => { "type" => "string" }
  }
}

result = client.generate(
  prompt: "Analyze the situation and decide next action.",
  schema: schema
)

puts result["action"]      # => "search"
puts result["reasoning"]    # => "User needs data..."
```

### 4.2: Generate (Plain Text)

```ruby
client = Ollama::Client.new

# Use allow_plain_text: true to skip schema requirement
response = client.generate(
  prompt: "Explain Ruby blocks in one sentence.",
  allow_plain_text: true
)

puts response  # => Plain text/markdown response (String)
```

### 4.3: Chat (Human-Facing Interfaces)

```ruby
# Enable chat in config
config = Ollama::Config.new
config.allow_chat = true
client = Ollama::Client.new(config: config)

response = client.chat(
  messages: [
    { role: "user", content: "Hello!" }
  ],
  allow_chat: true
)

puts response["message"]["content"]
```

### 4.4: ChatSession (Stateful Conversations)

```ruby
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true
client = Ollama::Client.new(config: config)

observer = Ollama::StreamingObserver.new do |event|
  print event.text if event.type == :token
end

chat = Ollama::ChatSession.new(
  client,
  system: "You are a helpful assistant.",
  stream: observer
)

chat.say("Hello!")
chat.say("Explain Ruby blocks")
```

### 4.5: Planner Agent (Schema-Based Planning)

```ruby
client = Ollama::Client.new

planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

# Define the decision schema
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

### 4.6: Executor Agent (Tool-Calling)

```ruby
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

### 4.7: Embeddings

```ruby
client = Ollama::Client.new

embedding = client.embeddings.embed(
  model: "all-minilm",
  input: "What is Ruby?"
)

puts embedding.length  # => Array of floats
```

---

## Complete Example: From Zero to Working Client

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Step 1: Require the gem
require "ollama_client"

# Step 2: Create client (using environment variables from .env)
config = Ollama::Config.new
config.base_url = ENV["OLLAMA_BASE_URL"] || "http://localhost:11434"
config.model = ENV["OLLAMA_MODEL"] || "llama3.1:8b"
config.temperature = ENV["OLLAMA_TEMPERATURE"].to_f if ENV["OLLAMA_TEMPERATURE"]

client = Ollama::Client.new(config: config)

# Step 3: Use the client
begin
  result = client.generate(
    prompt: "Return a JSON object with a 'greeting' field saying hello.",
    schema: {
      "type" => "object",
      "required" => ["greeting"],
      "properties" => {
        "greeting" => { "type" => "string" }
      }
    }
  )
  
  puts "✅ Success!"
  puts "Response: #{result['greeting']}"
rescue Ollama::Error => e
  puts "❌ Error: #{e.message}"
end
```

---

## Configuration Options Reference

| Option | Default | Description |
|--------|---------|-------------|
| `base_url` | `"http://localhost:11434"` | Ollama server URL |
| `model` | `"llama3.1:8b"` | Default model to use |
| `timeout` | `20` | Request timeout in seconds |
| `retries` | `2` | Number of retry attempts on failure |
| `temperature` | `0.2` | Model temperature (0.0-2.0) |
| `top_p` | `0.9` | Top-p sampling parameter |
| `num_ctx` | `8192` | Context window size |
| `allow_chat` | `false` | Enable chat API (must be explicitly enabled) |
| `streaming_enabled` | `false` | Enable streaming support |

---

## Next Steps

- See [README.md](../README.md) for detailed API documentation
- See [PERSONAS.md](PERSONAS.md) for using personas
- See [examples/](../examples/) for complete working examples

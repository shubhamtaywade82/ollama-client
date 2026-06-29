# Ollama::Client

[![CI](https://github.com/shubhamtaywade82/ollama-client/actions/workflows/main.yml/badge.svg)](https://github.com/shubhamtaywade82/ollama-client/actions)
[![Gem Version](https://badge.fury.io/rb/ollama-client.svg)](https://rubygems.org/gems/ollama-client)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-ruby.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)

> **The production-safe Ruby AI SDK for Ollama.**

A failure-aware, contract-driven client that wraps the Ollama API in clean, idiomatic Ruby. Built for correctness, determinism, and zero-magic reliability.

---

## Why ollama-client?

Other Ollama clients give you raw HTTP hashes. This SDK gives you **production guarantees** and a native Ruby developer experience.

### 1. Failure-Aware By Design

| What goes wrong | What other gems do | What `ollama-client` does |
|---|---|---|
| Model isn't downloaded | Raise error | Auto-pull → retry |
| Ollama server is down | Hang for 60s | Fast-fail instantly |
| LLM returns broken JSON | Crash your JSON parser | Repair prompt → retry |
| Request times out | Raise immediately | Exponential backoff |
| Schema violation | You find out in production | `SchemaViolationError` before it reaches your code |

### 2. Ruby Objects Everywhere

Stop parsing raw JSON strings or dig-digging through nested string hashes. 

```ruby
# Other gems
response["message"]["content"]
response["total_duration"]

# ollama-client
response.message.content
response.total_duration
```

---

## Installation

```ruby
bundle add ollama-client
```

---

## Configuration

Set up your client globally (e.g. in a Rails initializer) or construct thread-safe local configs for concurrent background jobs.

```ruby
# config/initializers/ollama.rb
Ollama.configure do |config|
  config.default_model = "qwen2.5-coder:7b"
  config.base_url = ENV["OLLAMA_URL"] || "http://localhost:11434"
  config.timeout = 30
  config.retries = 2
end
```

---

## Testing Without a Live Server

Don't let your test suite depend on a running Ollama server. `ollama-client` ships with zero-dependency mocking helpers:

```ruby
# spec/spec_helper.rb or rails_helper.rb
require "ollama/testing"

RSpec.configure do |config|
  config.include Ollama::Testing
  config.before(:each) { clear_ollama_stubs }
end

# In your spec file
it "generates a summary" do
  stub_ollama_chat(content: "This is a mocked summary.")
  
  client = Ollama::Client.new
  response = client.chat(messages: [{ role: "user", content: "..." }])
  expect(response.content).to eq("This is a mocked summary.")
end
```

---

## Core DSLs: Writing Clean Ruby

### 1. Prompt DSL
Encapsulate your prompt templates into reusable class objects.

```ruby
class ExplainCode < Ollama::Prompt
  input :code, :language
  system "You are a senior Ruby engineer."
  user { "Explain this #{language} implementation:\n#{code}" }
end

# Usage:
prompt = ExplainCode.new(code: "def foo; end", language: "Ruby")
client.chat(messages: prompt.to_h)
```

### 2. Tool DSL
Define type-safe tools that serialize automatically into standard JSON schemas.

```ruby
class WeatherTool < Ollama::ToolDSL
  description "Get current weather for a city"
  tool_name "get_weather"

  input do
    string :city, description: "The name of the city"
    string :unit, optional: true, default: "celsius"
  end

  call do
    # Define tool action or handle execution
  end
end

# Usage:
client.chat(
  messages: [{ role: "user", content: "What is the weather in London?" }],
  tools: [WeatherTool.to_tool_hash]
)
```

### 3. Structured Outputs (Schema DSL)
Force the model to output valid JSON matching your schema structure.

```ruby
class TradeSignal < Ollama::SchemaDSL
  string :action, enum: ["BUY", "SELL", "HOLD"]
  number :confidence, description: "Confidence score from 0 to 1"
end

# Usage:
result = client.generate(
  prompt: "Analyze the current AAPL price trend.",
  schema: TradeSignal.to_tool_hash # Generates valid JSON schema
)
result["action"]     # => "BUY"
result["confidence"] # => 0.95
```

---

## Real-World Rails Patterns

### In a Controller (Streaming Chat)
```ruby
class ChatsController < ApplicationController
  def create
    client = Ollama::Client.new
    
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Last-Modified"] = Time.now.httpdate

    client.chat(
      messages: [{ role: "user", content: params[:message] }],
      hooks: {
        on_token: ->(token) { response.stream.write(token) }
      }
    )
  ensure
    response.stream.close
  end
end
```

### In a Service Object (RAG Embeddings)
```ruby
class DocumentIndexer
  def initialize(document)
    @document = document
    @client = Ollama::Client.new
  end

  def index!
    vectors = @client.embeddings.embed(
      model: "nomic-embed-text",
      input: @document.content
    )
    
    @document.update!(embedding: vectors)
  end
end
```

---

## Core API & Endpoint Coverage

### Chat (Multi-turn)
```ruby
response = client.chat(
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "What is Ruby?" }
  ]
)
response.message.content  # => "Ruby is a dynamic..."
response.done?            # => true
```

### Generate (Prompt -> Completion)
```ruby
client.generate(prompt: "Explain blocks in Ruby.")
# => "Blocks are anonymous closures..."
```

### Thinking Mode (DeepSeek-R1 / Qwen Reasoning)
```ruby
response = client.chat(
  model: "deepseek-r1",
  messages: [{ role: "user", content: "Solve: 2x + 5 = 15" }],
  think: true
)
response.message.thinking # => "Subtract 5 from both sides... divide by 2..."
response.message.content  # => "Therefore, x = 5."
```

### Model Management
```ruby
client.list_models        # Returns models with capability profiles
client.pull("qwen3.5:4b") # Pull new model
client.delete_model(model: "old-model")
```

---

## Advanced

### Composable Middleware Pipeline
```ruby
client = Ollama::Client.new
client.use Ollama::Middleware::Logger # Logs requests/responses
client.use MyCustomMiddleware
```

### OpenAI Compatibility
```ruby
require "ollama/openai"

client = Ollama::Client.new
client.openai.chat.completions.create(
  model: "qwen2.5-coder:7b",
  messages: [{ role: "user", content: "hello" }]
)
```

---

## License

MIT. See [LICENSE.txt](LICENSE.txt).

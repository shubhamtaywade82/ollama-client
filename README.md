# Ollama::Client

[![CI](https://github.com/shubhamtaywade82/ollama-client/actions/workflows/main.yml/badge.svg)](https://github.com/shubhamtaywade82/ollama-client/actions)
[![Gem Version](https://badge.fury.io/rb/ollama-client.svg)](https://rubygems.org/gems/ollama-client)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-ruby.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)

> **A production-safe Ollama client for Rails & agent systems.**

Not a chatbot UI. Not a 1:1 API wrapper.
A failure-aware, contract-driven client that covers **all 12 Ollama API endpoints** with production guarantees.

**Correctness. Determinism. Failure-aware design. Nothing else.**

## Why This Gem Exists

Other Ollama clients give you raw HTTP access. This one gives you **production guarantees**:

| What goes wrong | What other gems do | What `ollama-client` does |
|---|---|---|
| Model isn't downloaded | Raise error | Auto-pull → retry |
| Ollama server is down | Hang for 60s | Fast-fail instantly |
| LLM returns broken JSON | Crash your parser | Repair prompt → retry |
| Request times out | Raise immediately | Exponential backoff |
| Schema violation | You find out in prod | `SchemaViolationError` before it reaches your code |

## Installation

```ruby
gem "ollama-client"
```

## Quick Start

Works out of the box — all defaults are production-safe:

```ruby
require "ollama_client"

client = Ollama::Client.new
# model: "llama3.1:8b", timeout: 30, retries: 2, strict_json: true
```

### Chat (Multi-turn Conversations)

The primary endpoint for agentic usage:

```ruby
response = client.chat(
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "What is Ruby?" }
  ]
)

response.message.content  # => "Ruby is a dynamic, open source..."
response.message.role     # => "assistant"
response.done?            # => true
response.done_reason      # => "stop"
response.total_duration   # => 1234567 (nanoseconds)
```

#### Tool Calling

```ruby
messages = [{ role: "user", content: "What is the weather in London?" }]

tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get weather for a city",
      parameters: {
        type: "object",
        properties: { city: { type: "string" } },
        required: ["city"]
      }
    }
  }
]

response = client.chat(messages: messages, tools: tools)
response.message.tool_calls.first.name       # => "get_weather"
response.message.tool_calls.first.arguments  # => { "city" => "London" }
```

#### Structured Output (JSON Schema)

```ruby
messages = [{ role: "user", content: "What is the capital of France? Answer in JSON." }]
schema = { type: "object", properties: { answer: { type: "string" } } }

response = client.chat(messages: messages, format: schema)
JSON.parse(response.message.content)  # => { "answer" => "Paris" }
```

#### Thinking Mode

> **Note:** Requires a thinking-capable model (e.g. `deepseek-coder:6.7b`, `qwen3:0.6b`).

```ruby
messages = [{ role: "user", content: "What is the square root of 144?" }]

response = client.chat(messages: messages, model: "qwen3:0.6b", think: true)
response.message.thinking  # => "Let me reason through this..."
response.message.content   # => "The answer is 12."
```

#### Chat Options

```ruby
messages = [{ role: "user", content: "Hello" }]

client.chat(
  messages: messages,
  model: "qwen2.5-coder:7b",             # Override default model
  options: { temperature: 0.8 }, # Runtime options
  keep_alive: "10m",           # Keep model loaded
  logprobs: true,              # Return log probabilities
  top_logprobs: 5
)
```

### Generate (Prompt → Completion)

```ruby
client.generate(prompt: "Explain Ruby blocks in one sentence.")
# => "Ruby blocks are anonymous closures passed to methods..."
```

#### Structured JSON (Agents / Planners)

```ruby
schema = {
  "type" => "object",
  "required" => ["action", "confidence"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "calculate", "finish"] },
    "confidence" => { "type" => "number" }
  }
}

result = client.generate(prompt: "User wants weather in Paris.", schema: schema)
result["action"]     # => "search"
result["confidence"] # => 0.95
```

If the LLM returns invalid JSON, the client automatically retries with a repair prompt. You get valid output or a typed exception — never a silent failure.

#### Structured Thinking (Zero-Magic CoT extraction)

You can ask reasoning models to output their thoughts separately from the final answer. `ollama-client` enforces this via strict JSON schema prompting.

> **Note:** Requires a thinking model. Supported defaults: `/deepseek/i`, `/qwen/i`, `/r1/i`.

```ruby
schema = {
  "type" => "object",
  "required" => ["decision"],
  "properties" => {
    "decision" => { "type" => "string" }
  }
}

result = client.generate(
  model: "deepseek-r1",
  prompt: "Should we BUY or WAIT?",
  schema: schema,
  think: true,
  return_reasoning: true
)

result["reasoning"]          # => "...step by step analysis..."
result["final"]["decision"]  # => "WAIT"
```

#### Generate Options

```ruby
client.generate(
  prompt: "Write a poem",
  model: "qwen3:0.6b",               # Explicitly use a thinking model
  system: "You are a poet",          # System prompt
  think: true,                       # Thinking output
  keep_alive: "5m",                  # Keep model loaded
  options: { temperature: 0.8 }      # Runtime options
)
```

### Streaming (Observer Hooks)

No raw SSE. No state corruption risk. Works with both `chat` and `generate`:

```ruby
# Stream generate tokens
client.generate(
  prompt: "Write a haiku about code.",
  hooks: {
    on_token:    ->(token) { print token },
    on_error:    ->(err)   { warn err.message },
    on_complete: ->        { puts "\nDone" }
  }
)

# Stream chat tokens with log probabilities
client.chat(
  messages: [{ role: "user", content: "Tell me a story" }],
  logprobs: true,
  hooks: {
    # If your block takes 2 args, it receives the logprobs array for that token
    on_token: ->(token, logprobs) {
      print token
      # logprobs is an Array of Hashes, e.g. [{"token"=>"Once", "logprob"=>-0.12}, ...]
    },
    on_complete: -> { puts }
  }
)
```

### Embeddings (RAG)

```ruby
client.embeddings.embed(model: "nomic-embed-text:latest", input: "What is Ruby?")
# => [0.12, -0.05, 0.88, ...]

# Batch embeddings
client.embeddings.embed(model: "nomic-embed-text:latest", input: ["text1", "text2"])

# With options
client.embeddings.embed(
  model: "nomic-embed-text:latest",
  input: "text",
  truncate: true,        # Truncate long inputs
  dimensions: 256,       # Embedding dimensions
  keep_alive: "5m"       # Keep model loaded
)
```

### Model Management

```ruby
client.list_models              # Returns models with details & automatic capabilities map
# => [{ "name" => "llama3.1", "capabilities" => { "tools" => true, "thinking" => false, ... }, ... }]
client.list_model_names         # Just names: ["qwen2.5-coder:7b", "llama3.1:8b", ...]
client.list_running             # Currently loaded models (aliased as `ps`)
client.show_model(model: "qwen2.5-coder:7b")           # Model details, capabilities
client.show_model(model: "qwen2.5-coder:7b", verbose: true)  # Include model_info
client.pull("llama3.1:8b")                      # Download a model
client.delete_model(model: "old-model")      # Remove a model
client.copy_model(source: "qwen2.5-coder:7b", destination: "qwen2.5-coder:7b-backup")
client.create_model(model: "my-model", from: "qwen2.5-coder:7b", system: "You are Alpaca")
client.push_model(model: "user/my-model")    # Push to registry
client.version                               # => "0.12.6"
```

### Runtime Options

Pass via `options:` on `chat` or `generate`:

```ruby
messages = [{ role: "user", content: "Tell me a joke" }]

options = Ollama::Options.new(
  temperature: 0.7,
  num_predict: 256,
  stop: ["END"],
  presence_penalty: 0.5,
  frequency_penalty: -0.3
)

client.chat(messages: messages, options: options.to_h)
```

<details>
<summary>All supported options</summary>

| Option | Type | Description |
|---|---|---|
| `temperature` | Float (0–2) | Sampling temperature |
| `top_p` | Float (0–1) | Nucleus sampling |
| `top_k` | Integer | Top-K sampling |
| `num_ctx` | Integer | Context window size |
| `num_predict` | Integer | Max tokens to generate |
| `repeat_penalty` | Float (0–2) | Repeat penalty |
| `seed` | Integer | Random seed |
| `stop` | Array | Stop sequences |
| `tfs_z` | Float | Tail-free sampling |
| `mirostat` | 0/1/2 | Mirostat sampling mode |
| `mirostat_tau` | Float | Mirostat target entropy |
| `mirostat_eta` | Float | Mirostat learning rate |
| `typical_p` | Float (0–1) | Typical-p sampling |
| `presence_penalty` | Float (-2–2) | Presence penalty |
| `frequency_penalty` | Float (-2–2) | Frequency penalty |
| `num_gpu` | Integer | GPU layers |
| `num_thread` | Integer | CPU threads |
| `num_keep` | Integer | Tokens to keep for context |

</details>

## CLI

A strict, JSON-first CLI ships with the gem:

```bash
# Generate text
ollama-client generate --prompt "Explain Ruby blocks"

# Structured output with schema
echo '{"type":"object","properties":{"category":{"type":"string"}}}' > schema.json
ollama-client generate --prompt "Classify this" --schema schema.json --json

# Stream tokens
ollama-client generate --prompt "Write a poem" --stream

# Embeddings
ollama-client embed --input "What is Ruby?" --model nomic-embed-text:latest

# List models
ollama-client models

# Pull a model
ollama-client pull llama3.1:8b
```

All errors output as structured JSON to stderr. No hidden behavior.

## Console (Debug Mode)

```bash
bin/console
```

```ruby
verbose!  # Enable HTTP request/response logging
quiet!    # Disable it

client = Ollama::Client.new
client.version  # Prints full HTTP request/response to STDERR
```

## Failure Behaviors

| Scenario | What happens |
|---|---|
| **Model missing (404)** | Auto-pull → retry your request |
| **Server unreachable** | Instant `Ollama::Error` — no waiting |
| **Timeout** | Exponential backoff (`2^attempt` seconds) |
| **Invalid JSON** | Repair prompt → retry → `InvalidJSONError` if exhausted |
| **Schema violation** | Repair prompt → retry → `SchemaViolationError` if exhausted |
| **Streaming error** | `StreamError` raised with Ollama's error message |

## v1.0 Stability Contract

The public API is locked. See [API_CONTRACT.md](API_CONTRACT.md) for the full specification.

1. All method signatures are stable until v2.0
2. Error class hierarchy is stable until v2.0
3. Recovery behaviors (auto-pull, backoff, repair) are guaranteed
4. No silent coercion of malformed JSON — ever
5. Typed errors over generic exceptions — always

## Testing

```bash
# Unit + lint
bundle exec rake

# Integration (requires running Ollama)
OLLAMA_INTEGRATION=1 bundle exec rspec spec/integration/
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).

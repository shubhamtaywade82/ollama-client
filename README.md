# Ollama::Client (v1.0.0)

> A production-safe Ollama client for Rails & agent systems.

This is **NOT** a cosmetic wrapper or a chatbot UI library.
It is an opinionated, failure-aware client designed to enforce invariants when connecting your production applications or deterministic agent planners to a local or remote Ollama instance.

Prioritizing **correctness, determinism, and failure-aware design over feature volume**.

## 🎯 Positioning

There are several Ruby clients for Ollama. Why choose this one?

### Why this gem exists
*   **Predictable Failures**: What happens when your background job hits Ollama and the model isn't downloaded yet? What happens if it returns invalid JSON when your schema mandated it? This client handles these automatically (auto-pulling the model, structured repair prompts) instead of throwing obscure parse errors.
*   **Rails & Sidekiq Safe**: Opinionated defaults (`timeout: 30`, `retries: 2`). Implements exponential backoff on timeouts. Fast-fails when the server is genuinely unreachable.
*   **No Silent Coercions**: If a JSON schema is provided, the library will enforce strictly parsed JSON. It does not implicitly fall back to plain-text string mapping.
*   **Opt-in Observability**: Streaming is supported via observer callbacks (`on_token`, `on_error`, `on_complete`) rather than leaking raw SSE connections that corrupt your application state.

### Comparison

| Feature / Trait | `ollama-client` (This Gem) | `ollama-ruby` / `ollama-ai` |
| :--- | :--- | :--- |
| **Focus** | Production Rails & deterministic agents | General-purpose API wrapper |
| **Philosophy** | Failure-aware, strict contracts, minimal | Feature-complete 1:1 API mappings |
| **JSON Repair** | Automated repair prompts on parse failure | Manual |
| **Missing Model**| Auto-pulls the model lazily and retries | Raises instant error |
| **Timeouts** | Exponential backoff retries | Standard HTTP raises |
| **Footprint** | Surgical (`/generate`, `/embeddings`, etc) | Massive (Chat, UI, Vision, etc) |

### When NOT to use this gem
Do **not** use `ollama-client` if:
*   You are building a Chatbot UI and want a stateful conversation thread abstraction.
*   You need specialized domain endpoints like Vision parsing or raw file uploading.
*   You want a 1:1 DSL mapping of every API parameter Ollama offers.

## 🔒 v1.0 Stability Contract

With the release of `v1.0.0`, the public API of this gem is locked.
1. All public methods have explicit contracts.
2. The gem will fail loudly and predictably.
3. No silent coercion of malformed JSON.
4. Typed error classes (`Ollama::TimeoutError`, `Ollama::InvalidJSONError`, `Ollama::SchemaViolationError`) are preferred over generic exceptions.
5. We guarantee no backwards-incompatible API changes before `v2.0.0`.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ollama-client"
```

## Quick Start

The defaults are opinionated out-of-the-box for production stability:

```ruby
require "ollama_client"

client = Ollama::Client.new(
  config: Ollama::Config.new.tap do |c|
    c.model = "llama3.2"
    c.timeout = 30
    c.retries = 2
    c.strict_json = true
  end
)
```

### 1. Simple Generation

```ruby
response = client.generate(prompt: "Explain Ruby blocks in one sentence.")
puts response
# => "Ruby blocks are anonymous functions..."
```

### 2. Structured Agents (Planners)

```ruby
schema = {
  "type" => "object",
  "required" => ["action", "confidence"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "calculate", "finish"] },
    "confidence" => { "type" => "number" }
  }
}

# If the LLM generates invalid JSON, `ollama-client` will intercept the failure
# and automatically append a repair prompt, retrying the request seamlessly.
result = client.generate(
  prompt: "User wants weather in Paris. What should I do?",
  schema: schema
)

puts result["action"]     # => "search"
puts result["confidence"] # => 0.95
```

### 3. Streaming (Observer Hooks)

We **do not expose raw SSE streams** to prevent state corruption. Pass observer callbacks:

```ruby
client.generate(
  prompt: "Write a haiku about code.",
  hooks: {
    on_token: ->(token) { print token },
    on_error: ->(err) { puts "\nError: #{err.message}" },
    on_complete: -> { puts "\nDone!" }
  }
)
```

### 4. Fetching Embeddings (RAG)

```ruby
vectors = client.embeddings.embed(model: "all-minilm", input: "What is Ruby?")
# => [0.12, -0.05, 0.88, ...]
```

## Failure Behaviors

* **Model Missing (HTTP 404)**: If you request a model that isn't downloaded, the client catches the `NotFoundError`, calls `/pull` automatically, blocks until downloaded, and retries your original request.
* **Server Unreachable (ECONNREFUSED)**: Fails fast instantly. We won't spin your background worker for 60 seconds waiting for a server that isn't running.
* **Timeout Errors**: Caught internally. Retried automatically adhering to exponential backoff (`sleep(2 ** attempts)`).
* **Malformed JSON**: When `strict_json` is enabled (default), a `SchemaViolationError` or `InvalidJSONError` triggers an automatic repair request under the hood, injecting a `CRITICAL FIX` instruction. You get valid JSON, or a typed exception if retries exhaust.

See `examples/` for more detailed patterns.

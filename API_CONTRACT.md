# API Contract — v1.0.0

This document defines the **public API surface** of `ollama-client` v1.0.
Everything listed here is guaranteed stable until `v2.0.0`.

## Public Methods

### `Ollama::Client`

```ruby
client = Ollama::Client.new(config: Ollama::Config.new)
```

#### Chat

| Method | Signature | Returns |
|---|---|---|
| `chat` | `(messages:, model: nil, format: nil, tools: nil, stream: nil, think: nil, keep_alive: nil, options: nil, logprobs: nil, top_logprobs: nil, hooks: {})` | `Ollama::Response` |

#### Generate

| Method | Signature | Returns |
|---|---|---|
| `generate` | `(prompt:, schema: nil, model: nil, strict: config.strict_json, return_meta: false, system: nil, images: nil, think: nil, keep_alive: nil, suffix: nil, raw: nil, options: nil, hooks: {})` | `String` (no schema) or `Hash` (with schema) |

#### Model Management

| Method | Signature | Returns |
|---|---|---|
| `list_models` | `()` | `Array<Hash>` |
| `list_model_names` | `()` | `Array<String>` |
| `list_running` / `ps` | `()` | `Array<Hash>` |
| `show_model` | `(model:, verbose: false)` | `Hash` |
| `pull` | `(model_name)` | `true` |
| `delete_model` | `(model:)` | `true` |
| `copy_model` | `(source:, destination:)` | `true` |
| `create_model` | `(model:, from:, system: nil, template: nil, license: nil, parameters: nil, messages: nil, quantize: nil, stream: false)` | `Hash` |
| `push_model` | `(model:, insecure: false, stream: false)` | `Hash` |
| `version` | `()` | `String` |
| `embeddings` | _(attr_reader)_ | `Ollama::Embeddings` instance |

### `Ollama::Embeddings`

```ruby
client.embeddings.embed(model: "nomic-embed-text:latest", input: "text")
```

| Method | Signature | Returns |
|---|---|---|
| `embed` | `(model:, input:, truncate: nil, dimensions: nil, keep_alive: nil, options: nil)` | `Array<Float>` (single) or `Array<Array<Float>>` (batch) |

### `Ollama::Response`

Returned by `chat`. Wraps the API response with accessor methods:

| Method | Returns | Description |
|---|---|---|
| `message` | `Ollama::Response::Message` | Message wrapper |
| `content` | `String` | Shorthand for `message.content` |
| `done?` | `Boolean` | Whether generation finished |
| `done_reason` | `String` | Why generation stopped (`"stop"`, etc.) |
| `model` | `String` | Model name used |
| `total_duration` | `Integer` | Total time (nanoseconds) |
| `load_duration` | `Integer` | Model load time |
| `prompt_eval_count` | `Integer` | Prompt token count |
| `eval_count` | `Integer` | Response token count |
| `logprobs` | `Array` | Log probabilities (when enabled) |

#### `Ollama::Response::Message`

| Method | Returns | Description |
|---|---|---|
| `content` | `String` | Message content |
| `thinking` | `String` | Thinking output (when `think: true`) |
| `role` | `String` | `"assistant"` |
| `tool_calls` | `Array<ToolCall>` | Function calls |
| `images` | `Array<String>` | Base64 images |

### `Ollama::Options`

Type-safe runtime options passed via `options:` parameter:

```ruby
Ollama::Options.new(temperature: 0.7, num_predict: 256)
```

Valid keys: `temperature`, `top_p`, `top_k`, `num_ctx`, `repeat_penalty`, `seed`, `num_predict`, `stop`, `tfs_z`, `mirostat`, `mirostat_tau`, `mirostat_eta`, `num_gpu`, `num_thread`, `num_keep`, `typical_p`, `presence_penalty`, `frequency_penalty`.

### `Ollama::Config`

All attributes are read/write via `attr_accessor`:

| Attribute | Type | Default | Description |
|---|---|---|---|
| `base_url` | `String` | `"http://localhost:11434"` | Ollama server URL |
| `model` | `String` | `"llama3.1:8b"` | Default model for generation |
| `timeout` | `Integer` | `30` | HTTP read/open timeout in seconds |
| `retries` | `Integer` | `2` | Max retry attempts |
| `strict_json` | `Boolean` | `true` | Enable JSON validation + repair |
| `temperature` | `Float` | `0.2` | Sampling temperature |
| `top_p` | `Float` | `0.9` | Nucleus sampling |
| `num_ctx` | `Integer` | `8192` | Context window size |
| `on_response` | `Proc/nil` | `nil` | Global response callback |

## Error Classes

All errors inherit from `Ollama::Error < StandardError`.

| Error | Raised When | Retryable? |
|---|---|---|
| `Ollama::Error` | Base class / connection failures | **No** — fast fail |
| `Ollama::TimeoutError` | `Net::ReadTimeout` / `Net::OpenTimeout` | **Yes** — exponential backoff |
| `Ollama::InvalidJSONError` | Response cannot be parsed as JSON | **Yes** — repair prompt retry |
| `Ollama::SchemaViolationError` | Parsed JSON fails schema validation | **Yes** — repair prompt retry |
| `Ollama::RetryExhaustedError` | All retry attempts exhausted | **No** — terminal |
| `Ollama::HTTPError` | Non-200 HTTP response | Depends on status code |
| `Ollama::NotFoundError` | HTTP 404 (model not found) | **Auto-handled** — triggers pull |
| `Ollama::StreamError` | `{"error": "..."}` in NDJSON stream | **No** — immediate |

## Recovery Behaviors (Guaranteed)

| Scenario | Behavior |
|---|---|
| Model missing (404) | Auto-pull once → retry original request |
| Timeout | Exponential backoff: `sleep(2 ** attempt)` |
| Invalid JSON (strict mode) | Append repair prompt → retry |
| Schema violation (strict mode) | Append repair prompt → retry |
| Server unreachable (ECONNREFUSED) | Immediate `Ollama::Error` — no retries |
| All retries exhausted | `Ollama::RetryExhaustedError` |
| Streaming error | `Ollama::StreamError` with server message |

## Streaming Hooks

Passed via `hooks:` parameter on `generate` and `chat`:

```ruby
hooks: {
  on_token:    ->(token) { ... },  # Called per token chunk
  on_error:    ->(error) { ... },  # Called on stream error
  on_complete: -> { ... }          # Called when stream finishes
}
```

Hooks are **observer-only** — they cannot modify the response. Streaming is auto-enabled when any hook is present.

## What Will NOT Change Before v2.0

1. Method signatures listed above
2. Error class hierarchy
3. Default config values
4. Recovery behaviors (auto-pull, backoff, repair)
5. JSON schema validation via `json-schema` gem
6. Observer-style hooks interface

## What MAY Change (Minor Versions)

- New optional keyword arguments on existing methods
- New error subclasses (always inheriting from existing hierarchy)
- Additional config attributes (always with backwards-compatible defaults)
- Performance improvements to retry/backoff timing

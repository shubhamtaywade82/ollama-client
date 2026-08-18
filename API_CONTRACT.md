# API Contract — v1.4.0

This document defines the **public API surface** of `ollama-client` v1.4.0.
Everything listed here is guaranteed stable until `v2.0.0` (unless explicitly marked as *may evolve* in minor releases).

## Public Methods

### `Ollama::Client`

```ruby
client = Ollama::Client.new(config: Ollama::Config.new)
```

#### Client — model profiles (v1.3+)

| Method | Signature | Returns |
|---|---|---|
| `profile` | `(model_name)` | `Ollama::ModelProfile` |
| `history_sanitizer` | `(model_name_or_profile, trace_store: nil)` | `Ollama::HistorySanitizer` |

#### Chat

| Method | Signature | Returns |
|---|---|---|
| `chat` | `(messages:, model: nil, format: nil, tools: nil, stream: nil, think: nil, keep_alive: nil, options: nil, logprobs: nil, top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil)` | `Ollama::Response` |

#### Generate

| Method | Signature | Returns |
|---|---|---|
| `generate` | `(prompt:, context: nil, schema: nil, model: nil, strict: config.strict_json, return_meta: false, system: nil, images: nil, think: nil, return_reasoning: false, keep_alive: nil, suffix: nil, raw: nil, options: nil, hooks: {}, tools: nil)` | `String` (no schema) or `Hash` (with schema) |

`context:` accepts the `context` array returned by a previous `generate` call (or via `return_meta: true`) for `/api/generate`-side conversational memory, independent of `chat`'s message history.

When `think: true` and `return_reasoning: true`, the return value is a `Hash` with:

- `"reasoning"` — the extracted reasoning text (may be empty string)
- `"final"` — either a `String` (no schema) or a `Hash` (when `schema:` is provided)

#### Model Management

| Method | Signature | Returns |
|---|---|---|
| `list_models` | `()` | `Array<Hash>` |
| `list_model_names` | `()` | `Array<String>` |
| `list_running` / `ps` | `()` | `Array<Hash>` |
| `show_model` | `(model:, verbose: false)` | `Hash` |
| `pull` | `(model_name, insecure: false, stream: false, hooks: {})` | `Hash` (final status) |
| `delete_model` | `(model:)` | `true` |
| `copy_model` | `(source:, destination:)` | `true` |
| `create_model` | `(model:, from: nil, modelfile: nil, path: nil, system: nil, template: nil, license: nil, parameters: nil, messages: nil, quantize: nil, stream: false)` | `Hash` |
| `push_model` | `(model:, insecure: false, stream: false, hooks: {})` | `Hash` (final status) |
| `blob_exists?` | `(digest:)` | `Boolean` |
| `create_blob` | `(digest:, content:)` | `true` |
| `load_model` | `(model:, keep_alive: "5m")` | `true` |
| `unload_model` | `(model:)` | `true` |
| `version` | `()` | `String` |
| `embeddings` | *(attr_reader)* | `Ollama::Embeddings` instance |

`pull` and `push_model` accept `hooks: { on_progress: ->(status) { ... } }`, invoked once per streamed NDJSON status line (`stream: true`) with the parsed status `Hash`.

#### Web Search (Ollama Cloud)

Require `config.base_url = "https://ollama.com"` and `config.api_key` / `OLLAMA_API_KEY`.

| Method | Signature | Returns |
|---|---|---|
| `web_search` | `(query:, max_results: nil)` | `Array<Hash>` (`"title"`, `"url"`, `"content"`) |
| `web_fetch` | `(url:)` | `Hash` (`"title"`, `"content"`, `"links"`) |

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

### `Ollama::GenerateStreamHandler` (v1.3+)

Used internally by `generate` when streaming; stable for advanced callers who process raw `Net::HTTPResponse` bodies.

| Method | Signature | Returns |
|---|---|---|
| `.call` | `(response, hooks, accumulator)` | `nil` — mutates `accumulator` (`String`) with decoded `response` tokens; invokes `hooks` |

### `Ollama::JsonFragmentExtractor` (v1.3+)

| Method | Signature | Returns |
|---|---|---|
| `.call` | `(text)` | `String` — a balanced JSON object or array substring (parse with `JSON.parse` if you need Ruby values) |

Raises `Ollama::InvalidJSONError` when `text` is blank or no balanced JSON fragment can be extracted.

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
| `api_key` | `String, nil` | `nil` | Optional Bearer token for Ollama Cloud (`https://ollama.com`) |
| `model` | `String` | `"qwen3.5:4b"` | Default model for generation |
| `timeout` | `Integer` | `30` | HTTP read/open timeout in seconds |
| `retries` | `Integer` | `2` | Max retry attempts |
| `strict_json` | `Boolean` | `true` | Enable JSON validation + repair |
| `temperature` | `Float` | `0.2` | Sampling temperature |
| `top_p` | `Float` | `0.9` | Nucleus sampling |
| `num_ctx` | `Integer` | `8192` | Context window size |
| `on_response` | `Proc/nil` | `nil` | Global response callback |

### Raw Escape Hatch

`client.raw` — direct HTTP access for endpoints without a dedicated method. Auth, retries, and error
mapping (`handle_http_error`) are applied the same as typed methods; the response body is JSON-parsed.

| Method | Signature | Returns |
|---|---|---|
| `raw.get` | `(path, query: nil)` | `Hash` |
| `raw.post` | `(path, payload: {}, query: nil)` | `Hash` |
| `raw.delete` | `(path, payload: nil, query: nil)` | `Hash` |

### OpenAI Compatibility Facade

`client.openai` — wraps `chat`, `generate`, `embeddings`, and `list_models` in OpenAI Chat Completions
API request/response shapes, for code written against OpenAI-shaped SDKs.

| Method | Signature | Returns |
|---|---|---|
| `openai.models.list` | `()` | `Hash` (`{"object"=>"list", "data"=>[...]}`) |
| `openai.embeddings.create` | `(model:, input:, **opts)` | `Hash` (`{"object"=>"list", "data"=>[...], "model"=>...}`) |
| `openai.chat.completions.create` | `(model:, messages:, tools: nil, temperature: nil, top_p: nil, **)` | `Hash` (OpenAI chat completion shape) |
| `openai.completions.create` | `(model:, prompt:, temperature: nil, top_p: nil, **)` | `Hash` (OpenAI text completion shape) |

## Policy Middleware (v1.4+)

`client.use(policy_class, **options)` attaches production-behavior middleware to the request
pipeline (chain order = registration order). All policies live under `Ollama::Policies::` and
wrap non-streaming requests; HTTP failures surface inside the chain as typed errors
(`Errors.from_response`), so policies observe 404/429/5xx responses.

| Policy | Options | Behavior |
|---|---|---|
| `Policies::Retry` | `max_attempts:`, `strategy:` (`:exponential`/`:linear`/`:fixed`/`:jitter`), `base_delay:`, `max_delay:`, `jitter:`, `retryable_errors:`, `hooks:` | Retries network errors and HTTP 429/5xx with backoff |
| `Policies::Timeout` | `connect_timeout:`, `read_timeout:`, `write_timeout:`, `hooks:` (`:on_timeout`) | Annotates `env[:timeouts]`; fires `:on_timeout` hook |
| `Policies::AutoPull` | `enabled:`, `allowed_patterns:` (glob), `hooks:` (`:before_pull`, `:after_pull`) | On 404, pulls the requested model once and retries the request |
| `Policies::Fallback` | `models:` (ordered list), `fallback_on:`, `hooks:` | Re-issues the request against each fallback model until one succeeds |
| `Policies::RateLimit` | `requests_per_second:`, `requests_per_minute:`, `burst:`, `hooks:` | Token-bucket throttling before dispatch |
| `Policies::CapabilityValidation` | `enabled:`, `cache:`, `cache_ttl:`, `hooks:` (`:capability_missing`) | Raises `UnsupportedCapabilityError` when the model profile lacks a requested capability (tools/thinking/vision/structured output) |
| `Policies::RepairJson` | `max_repairs:`, `strategies:` (`:balanced`, `:extract_object`), `hooks:` | Repairs malformed JSON response bodies |
| `Policies::SchemaRepair` | `max_repairs:`, `strict:`, `hooks:` | Validates structured output against the request `format` schema and repairs violations (missing fields, type mismatches, extras) |

## Agent Executor (v1.4+)

`Ollama::Agent::Executor` (required by the default load path) runs the chat + tool-calling loop:

| Method | Signature | Returns |
|---|---|---|
| `Executor#run` | `(system:, user:)` | `String` — final assistant content |
| `Executor#messages` | `()` | `Array<Hash>` — conversation history (system, user, assistant, tool turns) |

Constructor: `Executor.new(client, tools: { "name" => callable_or_tool }, max_steps: 20, stream: nil)`.
Tool keys may be strings or symbols. Pass `stream:` an `Ollama::StreamingObserver` to receive
`:token`, `:tool_call_detected`, and `:state` events.

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
| `Ollama::UnsupportedThinkingModel` | `think:` requested for a model that does not support reasoning | **No** |
| `Ollama::UnsupportedCapabilityError` | Multimodal or other capability used outside model profile | **No** |
| `Ollama::ThinkingFormatError` | Reasoning tags in model output could not be parsed | **No** |

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
  on_token:     ->(token) { ... },           # generate: token string; chat: token string
  on_thought:   ->(event) { ... },            # chat only: Ollama::StreamEvent (reasoning)
  on_tool_call: ->(tool_call_hash) { ... },   # chat only: tool call payload from final chunk
  on_error:     ->(error) { ... },
  on_complete:  -> { ... }
}
```

Hooks are **observer-only** — they cannot modify the response. For `chat`, streaming is auto-enabled when any hook is present (including `on_thought` or `on_tool_call`). For `generate`, streaming follows the same hook-driven rule as before.

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

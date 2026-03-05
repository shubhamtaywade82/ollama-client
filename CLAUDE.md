# ollama-client

Ruby gem — Ollama HTTP client for agent-grade usage. Provides `chat`, `generate`, embeddings, and full model management. Stable public API defined in `API_CONTRACT.md`.

## Stack

- Ruby gem (no Rails)
- Zeitwerk autoloader
- RSpec + WebMock + Timecop + SimpleCov
- RuboCop

## Commands

```bash
bundle exec rspec
COVERAGE=true bundle exec rspec
bundle exec rubocop
bundle exec rake
```

## Architecture

```
lib/ollama/
  client.rb             # Top-level entry point
  client/
    chat.rb             # chat() method
    generate.rb         # generate() method
    model_management.rb # list, pull, delete, copy, create, push, version
  config.rb             # Ollama::Config (base_url, model, timeout, retries, strict_json, etc.)
  response.rb           # Ollama::Response wrapper
  embeddings.rb         # client.embeddings.embed()
  options.rb            # Model options (temperature, top_p, num_ctx)
  dto.rb                # Data transfer objects
  schema_validator.rb   # JSON schema validation for structured output
  schemas/              # Built-in JSON schemas
  capabilities.rb       # Model capability detection
  errors.rb             # Error hierarchy
  version.rb
```

## Public API (stable — see API_CONTRACT.md)

- `client.chat(messages:, model:, tools:, stream:, think:, ...)` → `Ollama::Response`
- `client.generate(prompt:, schema:, model:, strict:, ...)` → `String` or `Hash`
- `client.embeddings.embed(model:, input:)` → `Array<Float>`
- Model management: `list_models`, `pull`, `delete_model`, `copy_model`, `create_model`, `push_model`, `version`

## Key rules

- **Never break the public API** — changes to method signatures require a version bump and API_CONTRACT.md update
- All HTTP calls must be mockable with WebMock — never require live Ollama in tests
- `Ollama::Config` defaults to `localhost:11434` — config is per-client, not global (thread-safe)
- `generate` with `schema:` returns a parsed Hash; without `schema:` returns raw String — never mix
- `strict_json: true` (default) — do not disable in production code
- Thread safety: per-client config is safe; modifying global config while clients are active is not

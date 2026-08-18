# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-08-18

### Added
- `Ollama::Policies::*` middleware is now **wired and public**: `client.use(Ollama::Policies::Retry, ...)` etc. attaches retry/timeout/auto-pull/fallback/rate-limit/capability-validation/JSON-repair/schema-repair policies to the request pipeline. The Rack-style `call(request, env)`/`@app` scaffolding was converted to the pipeline's `around` contract, and HTTP failures now surface as typed errors *inside* the chain (`Transport::Base#call` → `Errors.from_response`) so policies can observe 404/429/5xx responses. Documented in `API_CONTRACT.md`.
- `Ollama::Agent::Executor` is wired into the default load path and `#run` now uses the current `chat()` API (streaming via `hooks:`) instead of the removed `chat_raw`; tool keys may be strings or symbols.
- `SchemaViolationError` now carries structured `violations` (field/type data), raised by `SchemaValidator` and consumed by `SchemaRepair`.
- `Ollama::Schemas.tool_intent` is now the default schema for `client.generate_tool_intent`.
- `list_running`, `show_model`, and `version` now parse through `Parsers::{ListRunning,ShowModel,Version}` (previously dead files).
- Multi-API-key Ollama Cloud failover via `Ollama::Config#api_keys`, `OLLAMA_API_KEYS`, and automatic HTTP 429 rotation with `Ollama::RateLimitExhaustedError` when every key remains rate-limited.
- `ENABLE_MULTI_KEY_CONCURRENCY` / `Ollama::Config#enable_multi_key_concurrency` for thread-safe round-robin initial key distribution across concurrent requests.
- `Ollama::Client#web_search` and `#web_fetch` — Ollama Cloud `/api/web_search` and `/api/web_fetch` endpoints (see `API_CONTRACT.md`).

### Changed
- Repositioned gem identity from "agent-first" to "Ruby AI SDK for Ollama" in gemspec and README. No API, behavior, or config changes.

### Removed
- Genuinely dead duplicates with zero references: `lib/ollama/parsers/{list_models,model_management}.rb` and `lib/ollama/serializers/vision.rb`.

### Fixed
- Repository-wide dead-code/bug audit: 37 of 110 `lib/` files were never `require`d anywhere in the gem's load chain, so nothing ever caught several of them raising on load. All 110 files now load cleanly (enforced by `spec/ollama/all_files_load_spec.rb`).
  - `Ollama::Middleware::{Cache,Logger,Metrics,Tracing}` each reopened `Ollama::Middleware` (a class) as `module Middleware`, raising `TypeError` on load — the `client.use Ollama::Middleware::Logger` example in README.md has never worked. Fixed the reopening, two broken `require_relative` paths, and a missing `require "digest"`. `Tracing#before_request` also unconditionally called `request.headers`/`request.with_headers`, which `Ollama::Request` doesn't implement — guarded behind `respond_to?`.
  - `Ollama::Tool` (and `Tool::Function`/`Parameters`/`Property`) was never required by `lib/ollama_client.rb`, so `examples/tool_calling_direct.rb`, `tool_dto_example.rb`, and `structured_tools.rb` raised `NameError` immediately. Added to the default load path.
  - `Ollama::Agent::Executor#tool_definitions` had a stray, copy-pasted code fragment from `#infer_parameters` appended after its real `.map` block, referencing undefined locals — always raised `NameError`. Removed the fragment; the method now returns its intended array.
  - Fixed the two broken example scripts that use `Ollama::Agent`/`Ollama::Tool` to require what they need, and rewrote `tool_calling_direct.rb`'s use of the removed `chat_raw`/`allow_chat:` API to the current `chat()` (which already returns a full `Ollama::Response`, including `tool_calls`).
  - `lib/ollama/policies/*` (Retry, Timeout, AutoPull, RepairJson, SchemaRepair, Fallback, RateLimit, CapabilityValidation): fixed three broken `require_relative` paths and a `Retry`/`Retry::Strategies` naming collision that raised `TypeError: superclass mismatch`. Subsequently wired into the pipeline as `client.use` middleware — see the Added section above.
  - Removed the now-redundant top-level `lib/ollama/openai_compat.rb` (zero references anywhere; `Ollama::Client` already includes `OpenAICompat` directly). `lib/ollama/openai.rb`'s `require "ollama/openai"` (documented in README) is kept for backwards compatibility — it's a harmless no-op now, since `client.openai` already works without it.
  - `Ollama::Agent::Executor#run` still calls `Client#chat_raw`, a pre-refactor method that no longer exists (superseded by `chat()`), and is deliberately **not** added to the default load path — see the note in `lib/ollama/agent/executor.rb`: `docs/RUBYLLM_ADOPTION_MATRIX.md` section L tracks whether tool-execution loops belong in core or a separate `ollama-agent` gem as an open question. **Resolved in the Added section above: wired into the default load path on the current `chat()` API.**
  - Confirmed genuinely dead with zero references anywhere (code, docs, examples): `lib/ollama/parsers/{list_models,list_running,model_management,show_model,version}.rb`, `lib/ollama/serializers/vision.rb`, `lib/ollama/schemas/tool_intent.rb`. Since resolved: `list_running`/`show_model`/`version` parsers are wired into model management, `Schemas.tool_intent` is the default intent schema, and the remaining dead duplicates were removed (see Added/Removed above).

### Documentation
- `API_CONTRACT.md`: documented `hooks: { on_progress: }` on `pull`/`push_model`, and the full `create_model`/`pull` keyword signatures (previously only partially listed).

### Testing
- Added `spec/ollama/vcr/` — VCR-cassette specs replaying real, recorded Ollama Cloud responses for `chat` (incl. tools, `think:`, `format:`, streaming), `generate` (incl. `schema:`, `context`, streaming), `list_models`, `show_model`, `version`, `web_search`, and `web_fetch`. Cassettes are committed under `spec/cassettes/` and replay with no network access or API key required; see `spec/cassettes/README.md` for scope, rationale, and the re-recording workflow. `embeddings` and model-management mutation endpoints (`pull`/`push`/`create`/`delete`/`copy`) remain WebMock-only — Ollama Cloud has no embedding models and rejects those endpoints for a regular API key.
- A few real-response findings surfaced by recording: `chat(format:)` doesn't enforce/repair schema compliance the way `generate(schema:)` does (confirms the known gap in `docs/RUBYLLM_ADOPTION_MATRIX.md` C3); `generate`'s `context` field can be absent (`nil`) for Cloud-hosted chat-tuned models rather than always populated; `Ollama::Capabilities.for` doesn't yet recognize the `gptoss` family, so `show_model`'s derived capability hash reports `tools`/`thinking` as `false` for `gpt-oss:20b` even though the server's own `capabilities` array says otherwise (confirms `docs/RUBYLLM_ADOPTION_MATRIX.md` E3). No code changes made for these — they're documented via the new specs' comments, not fixed, since fixing them is separate roadmap work.

### CI/CD
- CI now also runs against Ruby 3.4, and splits `rspec`/`rubocop` into separate steps so failures are distinguishable at a glance.
- Added a `build` job that builds the gem, installs it, and verifies the public API loads — catches packaging regressions on every PR instead of only at release time.
- Added a `dependency-audit` job (`bundler-audit`) that fails the build on known CVEs in `Gemfile.lock`; fixed three vulnerable transitive dependencies it found (`erb`, `json`, `concurrent-ruby`, `addressable`).
- Added a `ci` gate job aggregating `test`/`build`/`dependency-audit` for a single required branch-protection check.
- Added a weekly CodeQL security-analysis workflow for Ruby.
- Added Dependabot for weekly Bundler and GitHub Actions dependency updates.
- `release.yml` now runs the full test suite and RuboCop before building/publishing a tagged gem.

## [1.3.0] - 2026-04-20

### Added
- Model capability layer: `Ollama::ModelProfile`, `Ollama::Capabilities`, `Ollama::PromptAdapters`, `Ollama::MultimodalInput`, `Ollama::HistorySanitizer`, and `Ollama::StreamEvent` for model-aware chat, multimodal ordering, and structured streaming events.
- `Ollama::Client#profile` and `#history_sanitizer` for resolving profiles and building history sanitizers from a model name or `ModelProfile`.
- Extended `Ollama::Client#chat` with optional `profile:`, `inputs:`, `logprobs:`, and `top_logprobs:`; chat streaming hooks may include `on_thought` and `on_tool_call` (see `API_CONTRACT.md`).
- `Ollama::GenerateStreamHandler` — NDJSON streaming consumer for `/api/generate` responses.
- `Ollama::JsonFragmentExtractor` — extracts a balanced JSON object or array from text that may include leading or trailing prose.
- `require "ollama-client"` loads the same stack as `require "ollama_client"` (hyphenated gem entrypoint).
- `dotenv` (~> 2.8) as a runtime dependency; `ollama_client` continues to call `Dotenv.overload` when loaded.
- `script/live_branch_smoke.rb` — optional live Ollama smoke runner for profiles, chat extensions, generate streaming, embeddings, etc. (see script header for env vars).

### Changed
- `Client::Generate` delegates streaming body handling to `GenerateStreamHandler` (behavior and hooks contract unchanged).

## [1.1.0] - 2026-03-17

### Added
- Ollama Cloud support via `Ollama::Config#api_key` and HTTPS `base_url` (e.g. `https://ollama.com`).
- `Ollama::Config#http_connection_options` to centralize Net::HTTP connection options (including SSL and timeouts).
- `Ollama::Config#inspect` now redacts `api_key` while keeping other attributes visible.

### Changed
- Chat, generate, embeddings, and model management HTTP calls now share connection-option logic but keep existing behavior.

## [1.0.0] - 2026-02-22

### Changed
- **Massive surface area reduction:** Removed `chat`, `chat_raw`, `call_chat_api`, `call_chat_api_raw`, and related endpoints.
- **Architectural Shift:** Removed all chatbot UI logic (`ChatSession`, `Personas`), abstract Agent implementations (`Planner`, `Executor`), and `DocumentLoader` to enforce strict low-level determinism.
- **API Contracts:** `Client#generate` now handles strict JSON schemas directly and implements resilient auto-recovery.
- **Defaults:** Opinionated defaults out-of-the-box (`timeout: 30`, `retries: 2`, `strict_json: true`).
- **Streaming Hooks:** Deprecated raw SSE streaming over `chat` in favor of safe observer callbacks (`on_token`, `on_error`, `on_complete`) on `generate`.
- **Model Auto-Pulling:** If `generate` receives a 404 Model Not Found, it attempts to synchronously `/pull` the model once, and then automatically retries generation.
- **JSON Repair Loop:** Provided `strict_json: true`, if a model hallucinates malformed JSON formatting (like wrapping in markdown code blocks), the client automatically loops a retry with a CRITICAL repair prompt to seamlessly fix the output.
- **Backoff:** Encountering a `Net::ReadTimeout` now triggers an exponential backoff sleep (`2 ** attempt`) between retries rather than immediately re-hammering the server.

### Security
- **Strict Error Boundaries:** Malformed payloads can no longer leak into application state due to strict `SchemaViolationError` bounding.
- **Fast-fail Networking:** Encountering `Errno::ECONNREFUSED` fast-fails immediately.

### Rationale
Version `1.0.0` repositions `ollama-client` away from a bloated general-purpose wrapper toward a production-safe, failure-aware adapter intentionally crafted for Headless Rails Jobs and Agent Systems. By severing chat tools and abstractions, the gem commits to a strictly deterministic API that doesn't collapse under back-pressure, missing models, or temporary JSON formatting hallucinations.

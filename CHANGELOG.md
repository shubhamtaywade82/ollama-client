# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-08-18

### Changed
- Repositioned gem identity from "agent-first" to "Ruby AI SDK for Ollama" in gemspec and README. No API, behavior, or config changes.

### Added
- Multi-API-key Ollama Cloud failover via `Ollama::Config#api_keys`, `OLLAMA_API_KEYS`, and automatic HTTP 429 rotation with `Ollama::RateLimitExhaustedError` when every key remains rate-limited.
- `ENABLE_MULTI_KEY_CONCURRENCY` / `Ollama::Config#enable_multi_key_concurrency` for thread-safe round-robin initial key distribution across concurrent requests.
- `Ollama::Client#web_search` and `#web_fetch` — Ollama Cloud `/api/web_search` and `/api/web_fetch` endpoints (see `API_CONTRACT.md`).

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

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

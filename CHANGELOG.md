## [Unreleased]

## [0.2.5] - 2026-01-22

- Add `Ollama::DocumentLoader` for loading files as context in queries
- Enhance README with context provision methods and examples
- Improve embeddings error handling and model usage guidance
- Add comprehensive Ruby guide documentation
- Update `generate()` method with enhanced functionality and usage examples
- Improve error handling across client and embeddings modules

## [0.2.3] - 2026-01-17

- Add per-call `model:` override for `Ollama::Client#generate`.
- Document `generate` model override usage in README.
- Add spec to cover per-call `model:` in 404 error path.

## [0.2.0] - 2026-01-12

- Add `Ollama::Agent::Planner` (stateless `/api/generate`)
- Add `Ollama::Agent::Executor` (stateful `/api/chat` tool loop)
- Add `Ollama::StreamingObserver` + disciplined streaming support (Executor only)
- Add `Ollama::Client#chat_raw` (full response body, supports tool calls)

## [0.1.0] - 2026-01-04

- Initial release

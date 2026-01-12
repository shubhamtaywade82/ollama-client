## [Unreleased]

- Add `Ollama::Agent::Planner` (stateless `/api/generate`)
- Add `Ollama::Agent::Executor` (stateful `/api/chat` tool loop)
- Add `Ollama::StreamingObserver` + disciplined streaming support (Executor only)
- Add `Ollama::Client#chat_raw` (full response body, supports tool calls)

## [0.1.0] - 2026-01-04

- Initial release

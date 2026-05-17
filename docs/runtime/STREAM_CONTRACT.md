# Stream Contract (Draft)

`ollama-client` is the canonical owner of stream semantics.

## Required runtime semantics

- Explicit lifecycle states
- Cancellation semantics (graceful vs immediate)
- UTF-8 safe chunk assembly
- SSE boundary correctness
- Backpressure and bounded buffering
- Error channel for malformed/incomplete events

## Contract direction

Higher-level gems (`ollama-stream`, `ollama-rails`, `ollama-agent`) compose on top of
core stream semantics and must not fork or redefine lifecycle guarantees.

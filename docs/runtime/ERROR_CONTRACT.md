# Error Contract

`ollama-client` owns typed runtime error taxonomy and response-to-error mapping.

## Principles

- Typed errors over generic exceptions
- Deterministic mapping from transport responses
- Retry-safe classification lives in core runtime contracts

## Direction

Higher-level repos should consume and extend behavior via policy, not redefine
base runtime error classes for transport/inference semantics.

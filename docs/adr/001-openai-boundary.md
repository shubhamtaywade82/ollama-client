# ADR-001: OpenAI Compatibility Boundary

## Context
OpenAI request/response semantics can contaminate Ollama-native runtime APIs.

## Decision
OpenAI compatibility is optional and loaded separately.

## Consequences
- cleaner core semantics
- better long-term extensibility
- easier extraction to dedicated gem

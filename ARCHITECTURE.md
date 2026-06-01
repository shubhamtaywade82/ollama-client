# Architecture

`ollama-client` is a deterministic runtime kernel for local inference workloads in Ruby.

## Core responsibilities

- Transport abstraction and adapter boundaries
- Streaming runtime contracts
- Retry/policy execution hooks
- Structured output contracts
- Model lifecycle APIs
- Observability hooks (not full exporters)

## Core non-goals

- Vector DB abstractions
- RAG pipelines
- Prompt-template DSLs
- Workflow engines
- Memory systems

## Boundary rule

Core never depends on higher-level ecosystem gems.

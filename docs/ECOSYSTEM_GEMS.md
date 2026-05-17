# Ollama Ruby Ecosystem Blueprint

This repository remains the deterministic core runtime (`ollama-client`).

## Proposed Gem Split

- `ollama-client` (core): transport, retries, schema enforcement, model lifecycle, raw endpoint access, OpenAI facade.
- `ollama-openai`: standalone OpenAI protocol adapter for external OpenAI SDK consumers (currently provided as an optional extension via `require "ollama/openai"` as an interim step).
- `ollama-stream`: advanced streaming runtime (SSE object model, resumable streams, WS relay, backpressure primitives).
- `ollama-observability`: OpenTelemetry spans, metrics, token accounting, structured log emitters.
- `ollama-agent`: optional orchestration layer (tool runtime, memory, planners) kept separate from core transport.

## Gem Scaffolding Checklist

For each new gem:

1. `bundle gem <name> --mit --test=rspec --ci=github`
2. Add `README.md` with:
   - scope boundaries
   - compatibility matrix
   - migration guide
3. Add `sig/` RBS contracts for public APIs.
4. Add integration tests against local Ollama.
5. Publish with independent semver and changelog.

## Suggested Release Order

1. `ollama-openai` (highest interoperability impact)
2. `ollama-observability`
3. `ollama-stream`
4. `ollama-agent`

## Non-Goals for Core

Core should not include:

- vector DB abstractions
- prompt-chain DSLs
- opaque “magic” agent workflows

Keep core deterministic and infra-grade.

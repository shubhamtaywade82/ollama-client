# ADR-006: Stream Runtime Ownership

## Context
Streaming semantics were at risk of diverging across integrations and experimental repos.

## Decision
`ollama-client` owns canonical stream contracts (lifecycle, cancellation, buffering, ordering).

## Alternatives rejected
- per-integration stream semantics
- transport-specific user-facing stream APIs

## Consequences
- ecosystem-wide stream consistency
- cleaner adapter and integration layering
- reduced drift risk as streaming features expand

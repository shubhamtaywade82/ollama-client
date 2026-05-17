# ADR-002: Transport Abstraction

## Context
Direct HTTP coupling prevents adapter evolution and deterministic testing.

## Decision
All runtime HTTP execution goes through transport adapters.

## Consequences
- adapter extensibility (`:net_http`, `:mock`, future async)
- cleaner request pipeline layering
- improved testability

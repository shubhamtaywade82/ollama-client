# ADR-003: Normalized Transport Response

## Context
Runtime logic was coupled to backend-specific response objects.

## Decision
Introduce transport response object with normalized fields.

## Consequences
- transport-neutral policies and hooks
- easier observability
- incremental migration with compatibility shims

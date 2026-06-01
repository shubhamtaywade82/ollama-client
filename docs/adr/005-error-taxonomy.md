# ADR-005: Typed Error Taxonomy

## Context
Generic runtime errors made retry/policy behavior inconsistent and hard to classify.

## Decision
Define typed runtime/transport errors and centralized response-to-error mapping.

## Alternatives rejected
- status-code checks at call sites
- adapter-specific error hierarchies

## Consequences
- consistent retry-safe classification
- clearer policy layering
- improved observability and diagnostics

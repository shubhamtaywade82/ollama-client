# ADR-004: Mock Transport

## Context
Deterministic CI and failure simulation require decoupling tests from live Ollama servers.

## Decision
Introduce a `:mock` transport adapter in core transport architecture.

## Alternatives rejected
- Global monkeypatching HTTP
- Ad-hoc stubs per test

## Consequences
- deterministic request/response tests
- foundation for replay/latency/failure simulation
- enables test tooling without runtime coupling

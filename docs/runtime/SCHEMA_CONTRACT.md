# Schema Contract

`ollama-client` owns canonical schema/runtime semantics for deterministic structured generation.

## Scope

- Typed schema declarations
- Validation and coercion rules
- Repair strategy contracts
- Streaming structured output constraints

## Required semantics

- Deterministic parse contract: valid structured result or typed failure
- Coercion behavior must be explicit and documented
- Validation errors must be typed and machine-readable
- Repair paths must be bounded and observable

## Streaming requirements

- Incremental parse support
- Partial AST assembly guarantees
- Stream-time validation hooks
- Recovery behavior for malformed partial JSON

## Ownership rule

Higher-level gems may compose convenience APIs, but must not redefine core schema semantics.

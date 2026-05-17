# Transport Contract

`ollama-client` owns transport/runtime semantics.

## Adapter interface (current baseline)

- `request(uri:, request:, read_timeout:)`
- `stream(uri:, request:, &block)` (defined contract; implementation may be pending)
- `capabilities`

## Response contract

Adapters must return normalized transport responses with:

- `status`
- `headers`
- `body`
- `raw`
- `duration_ms`

Compatibility behavior for migration is allowed (e.g. status helper methods),
but response normalization remains mandatory.

## Ownership rule

No orchestration repo may redefine transport contracts. They consume this contract.

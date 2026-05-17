# Structured Outputs (Draft)

## Goals

- typed schema declarations
- coercion + validation
- repair strategies
- deterministic parse contracts

## Target APIs

```ruby
client.chat.parse(schema: TradeSignal)
client.chat.stream_parse(schema: TradeSignal)
```

## Streaming requirements

- incremental parse
- partial AST assembly
- stream-time validation
- repair during stream

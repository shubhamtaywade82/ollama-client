# Stream Runtime Design (Draft)

Target object:

```ruby
stream = client.chat.stream(...)
stream.each_token { |t| ... }
stream.each_chunk { |c| ... }
stream.cancel
stream.close
```

## Required semantics

- Explicit lifecycle: open -> active -> closing -> closed
- Cancellation modes: graceful vs immediate
- Backpressure: bounded buffering
- UTF-8 safe chunk assembly
- SSE event boundary correctness
- Error channel for malformed/incomplete events

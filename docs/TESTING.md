# Testing Guide: Client-Only Testing

This document explains how to test the `ollama-client` gem **in isolation**, focusing on **transport and protocol correctness**, not agent behavior.

## 🔒 Responsibility Boundary

`ollama-client` is responsible for:

✅ **Transport layer** - HTTP requests/responses  
✅ **Protocol correctness** - Request shaping, response parsing  
✅ **Schema enforcement** - JSON validation  
✅ **Tool-call parsing** - Detecting and extracting tool calls  
✅ **Error handling** - Network errors, timeouts, retries  
✅ **Streaming behavior** - NDJSON/SSE parsing  
✅ **Protocol compatibility** - Native Ollama + Anthropic adapter

`ollama-client` is **NOT** responsible for:

❌ Agent loops  
❌ Convergence logic  
❌ Policy decisions  
❌ Tool execution  
❌ Correctness of agent decisions

**If you test more than the transport layer, you're leaking agent concerns into the client.**

## Test Categories

### Category A: `/generate` Mode (Stateless, Deterministic)

Tests that prove `ollama-client` is safe-by-default for stateless operations.

#### ✅ G1 — Basic Generate

**Purpose:** Verify basic JSON parsing and response handling.

**Test:**
```ruby
it "parses JSON response from generate endpoint" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(
      status: 200,
      body: { response: '{"status":"ok"}' }.to_json
    )

  result = client.generate(
    prompt: "Output a JSON object with a single key 'status' and value 'ok'.",
    schema: { "type" => "object", "required" => ["status"] }
  )

  expect(result).to be_a(Hash)
  expect(result["status"]).to eq("ok")
  expect(result).not_to have_key("tool_calls")
end
```

**Assertions:**
- Response is a Hash
- JSON is parsed correctly
- No `tool_calls` present
- No streaming artifacts

#### ✅ G2 — Strict Schema Enforcement

**Purpose:** Validate contract enforcement (major differentiator).

**Test:**
```ruby
it "rejects responses that violate schema" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(
      status: 200,
      body: { response: '{"count":"not-a-number"}' }.to_json
    )

  schema = {
    "type" => "object",
    "required" => ["count"],
    "properties" => {
      "count" => { "type" => "number" }
    }
  }

  expect do
    client.generate(prompt: "Output JSON with key 'count' as a number.", schema: schema)
  end.to raise_error(Ollama::SchemaViolationError)
end
```

**Assertions:**
- Raises error if schema violated
- Rejects extra fields (if strict mode enabled)
- Validates required fields

#### ❌ G3 — Tool Attempt in Generate (Must Fail)

**Purpose:** Prove `/generate` is non-agentic by design.

**Test:**
```ruby
it "ignores tool calls in generate mode" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(
      status: 200,
      body: { response: '{"action":"call read_file tool on foo.rb"}' }.to_json
    )

  result = client.generate(
    prompt: "Call the read_file tool on foo.rb",
    schema: { "type" => "object" }
  )

  expect(result).not_to have_key("tool_calls")
  expect(result).not_to have_key("tool_use")
end
```

**Assertions:**
- No `tool_calls` parsed
- No silent acceptance of tool intent
- Either ignored or explicit error

### Category B: `/chat` Mode (Stateful, Tool-Aware)

Tests that prove `ollama-client` can **transport** tool calls and messages correctly — **not** that the agent works.

#### ✅ C1 — Simple Chat

**Purpose:** Verify basic message handling.

**Test:**
```ruby
it "handles simple chat messages" do
  stub_request(:post, "http://localhost:11434/api/chat")
    .to_return(
      status: 200,
      body: {
        message: { role: "assistant", content: "Hello!" }
      }.to_json
    )

  response = client.chat_raw(
    messages: [{ role: "user", content: "Say hello." }],
    allow_chat: true
  )

  expect(response.message.content).to eq("Hello!")
  expect(response.message.role).to eq("assistant")
end
```

**Assertions:**
- Response contains assistant message
- Message history preserved in request

#### ✅ C2 — Tool-Call Parsing (Critical)

**Purpose:** Verify client correctly **detects tool intent** (not execution).

**Test:**
```ruby
it "extracts tool calls from chat response" do
  stub_request(:post, "http://localhost:11434/api/chat")
    .to_return(
      status: 200,
      body: {
        message: {
          role: "assistant",
          content: "I'll call the ping tool.",
          tool_calls: [
            {
              type: "function",
              function: {
                name: "ping",
                arguments: { "x" => 1 }.to_json
              }
            }
          ]
        }
      }.to_json
    )

  response = client.chat_raw(
    messages: [{ role: "user", content: "If a tool named 'ping' exists, call it with { 'x': 1 }." }],
    tools: [tool_definition],
    allow_chat: true
  )

  tool_calls = response.message.tool_calls
  expect(tool_calls).not_to be_empty
  expect(tool_calls.first["function"]["name"]).to eq("ping")
  expect(JSON.parse(tool_calls.first["function"]["arguments"])).to eq("x" => 1)
end
```

**Assertions:**
- `tool_calls` extracted correctly
- Tool name parsed
- Arguments parsed as hash
- **No execution happens** (client must not execute tools)

#### ✅ C3 — Tool Result Round-Trip Formatting

**Purpose:** Verify client serializes tool messages correctly.

**Test:**
```ruby
it "serializes tool result messages correctly" do
  messages = [
    { role: "user", content: "Call ping tool" },
    { role: "assistant", content: "", tool_calls: [...] },
    { role: "tool", name: "ping", content: { ok: true }.to_json }
  ]

  stub_request(:post, "http://localhost:11434/api/chat")
    .with(body: hash_including(messages: messages))
    .to_return(
      status: 200,
      body: { message: { role: "assistant", content: "Done!" } }.to_json
    )

  response = client.chat_raw(messages: messages, allow_chat: true)
  expect(response.message.content).to eq("Done!")
end
```

**Assertions:**
- Client serializes tool message correctly
- Ollama accepts it
- Response parsed cleanly

### Category C: Protocol Adapters (Anthropic / Native)

Tests that prove **protocol adapter correctness** (pure client tests, no model required).

#### ✅ A1 — Anthropic Message Shape

**Purpose:** Verify request payload compatibility.

**Test:**
```ruby
it "serializes messages in Anthropic format" do
  stub_request(:post, "http://localhost:11434/api/chat")
    .with do |req|
      body = JSON.parse(req.body)
      expect(body["messages"]).to be_an(Array)
      expect(body["messages"].first).to include("role", "content")
    end
    .to_return(status: 200, body: { message: {} }.to_json)

  client.chat_raw(
    messages: [{ role: "user", content: "Test" }],
    allow_chat: true
  )
end
```

**Assertions:**
- Messages serialized as content blocks
- Tool calls emitted as `tool_use` (if Anthropic mode)
- Tool results serialized as `tool_result`

#### ✅ A2 — Anthropic Response Parsing

**Purpose:** Verify response normalization.

**Test:**
```ruby
it "normalizes Anthropic-style responses into internal format" do
  anthropic_response = {
    content: [
      {
        type: "tool_use",
        id: "call_123",
        name: "search",
        input: { q: "foo" }
      }
    ]
  }

  stub_request(:post, "http://localhost:11434/api/chat")
    .to_return(status: 200, body: anthropic_response.to_json)

  response = client.chat_raw(
    messages: [{ role: "user", content: "Search for foo" }],
    allow_chat: true
  )

  tool_calls = response.message.tool_calls
  expect(tool_calls).not_to be_empty
  expect(tool_calls.first["function"]["name"]).to eq("search")
end
```

**Assertions:**
- Client normalizes Anthropic format into internal `tool_calls`
- Protocol adapter correctness

### Category D: Failure Modes (Non-Negotiable)

#### ✅ F1 — Ollama Down

**Test:**
```ruby
it "handles connection refused gracefully" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_raise(Errno::ECONNREFUSED)

  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::Error)

  # Verify no hangs
  expect(Time.now - start_time).to be < 5
end
```

**Assertions:**
- Connection refused raises correct exception
- No hangs
- Retries handled correctly

#### ✅ F2 — Invalid JSON from Model

**Test:**
```ruby
it "raises error on invalid JSON response" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(status: 200, body: { response: "not json at all" }.to_json)

  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::InvalidJSONError)
end
```

**Assertions:**
- Client raises parse error
- Does not silently continue
- Retries handled (if retryable)

#### ✅ F3 — Streaming Interruption

**Test:**
```ruby
it "handles partial stream gracefully" do
  stub_request(:post, "http://localhost:11434/api/chat")
    .to_return(
      status: 200,
      body: "data: {\"message\":{\"content\":\"partial\"}}\n",
      headers: { "Content-Type" => "text/event-stream" }
    )

  # Simulate stream interruption
  expect do
    client.chat_raw(messages: [{ role: "user", content: "test" }], allow_chat: true)
  end.to raise_error(Ollama::Error)
end
```

**Assertions:**
- Partial stream handled
- Client terminates cleanly
- No corrupted state

## What You Should NOT Test

❌ **Do not test:**
- Infinite loops
- Retries based on content
- Agent stopping behavior
- Tool side effects
- Correctness of answers
- Agent convergence logic
- Policy decisions

**Those belong to `agent-runtime` and app repos.**

## Test Structure

The test suite is organized into focused spec files:

- `spec/ollama/client_spec.rb` - Basic client initialization and parameter validation
- `spec/ollama/client_generate_spec.rb` - Tests for `generate()` method (Category A)
- `spec/ollama/client_chat_spec.rb` - Tests for `chat()` method (Category B)
- `spec/ollama/client_chat_raw_spec.rb` - Tests for `chat_raw()` method (Category B)
- `spec/ollama/client_list_models_spec.rb` - Tests for `list_models()` method
- `spec/ollama/client_model_suggestions_spec.rb` - Tests for model suggestion feature
- `spec/ollama/errors_spec.rb` - Tests for all error classes (Category D)
- `spec/ollama/schema_validator_spec.rb` - Schema validation tests (Category A, G2)

## Running Tests

### Run All Tests
```bash
bundle exec rspec
```

### Run Specific Test File
```bash
bundle exec rspec spec/ollama/client_generate_spec.rb
```

### Run with Documentation Format
```bash
bundle exec rspec --format documentation
```

### Run Tests Matching a Pattern
```bash
bundle exec rspec -e "schema"
```

## Testing Strategy

### HTTP Mocking with WebMock

All HTTP requests are mocked using [WebMock](https://github.com/bblimke/webmock). This allows us to:
- Test without a real Ollama server
- Test error scenarios reliably
- Test retry logic deterministically
- Run tests in CI/CD without external dependencies

**Example:**
```ruby
stub_request(:post, "http://localhost:11434/api/generate")
  .to_return(status: 200, body: { response: '{"test":"value"}' }.to_json)
```

## Writing New Tests

### Basic Test Structure

```ruby
RSpec.describe Ollama::Client, "#method_name" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
      c.retries = 2
      c.timeout = 5
    end
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  it "does something" do
    stub_request(:post, "http://localhost:11434/api/generate")
      .to_return(status: 200, body: { response: '{}' }.to_json)

    result = client.generate(prompt: "test", schema: { "type" => "object" })
    expect(result).to eq({})
  end
end
```

## Best Practices

1. **Always mock HTTP requests** - Don't make real network calls in unit tests
2. **Test transport layer only** - Don't test agent behavior
3. **Test error paths** - Ensure all error scenarios are covered
4. **Test retry logic** - Verify retries work correctly
5. **Test edge cases** - JSON parsing, empty responses, etc.
6. **Keep tests focused** - One assertion per test when possible
7. **Use descriptive test names** - "it 'extracts tool calls from chat response'"
8. **Reset WebMock** - Always reset in `after` blocks

## Debugging Tests

### See WebMock Requests
```ruby
puts WebMock::RequestRegistry.instance.requested_signatures
```

### Inspect Stubbed Requests
```ruby
stub = stub_request(:post, "http://localhost:11434/api/generate")
  .with { |req| puts req.body }
  .to_return(status: 200, body: { response: '{}' }.to_json)
```

### Allow Real Requests (for debugging)
```ruby
WebMock.allow_net_connect!
```

## Common Issues

### "Real HTTP connections are disabled"
- Make sure `WebMock.disable_net_connect!` is called in `before` block
- Check that all requests are properly stubbed

### "Unregistered request"
- The request URL or method doesn't match the stub
- Check the exact URL being called
- Use `WebMock.allow_net_connect!` temporarily to see the real request

### Tests are flaky
- Ensure WebMock is reset in `after` blocks
- Don't share state between tests
- Use `let` instead of instance variables

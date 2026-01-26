# Test Checklist: `ollama-client` Client-Only Testing

This checklist ensures comprehensive testing of the `ollama-client` transport layer without leaking agent concerns.

## Category A: `/generate` Mode Tests (Stateless, Deterministic)

### ✅ G1 — Basic Generate
- [ ] Response is a Hash
- [ ] JSON is parsed correctly
- [ ] No `tool_calls` present
- [ ] No streaming artifacts
- [ ] Schema validation passes (if schema provided)

**Test File:** `spec/ollama/client_generate_spec.rb`

**Example Test:**
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

---

### ✅ G2 — Strict Schema Enforcement
- [ ] Raises error if schema violated
- [ ] Rejects extra fields (if strict mode enabled)
- [ ] Validates required fields
- [ ] Validates type constraints
- [ ] Validates enum constraints
- [ ] Validates number min/max
- [ ] Validates string minLength/maxLength

**Test File:** `spec/ollama/client_generate_spec.rb` or `spec/ollama/schema_validator_spec.rb`

**Example Test:**
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

---

### ❌ G3 — Tool Attempt in Generate (Must Fail)
- [ ] No `tool_calls` parsed
- [ ] No silent acceptance of tool intent
- [ ] Either ignored or explicit error
- [ ] `/generate` remains non-agentic

**Test File:** `spec/ollama/client_generate_spec.rb`

**Example Test:**
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

---

## Category B: `/chat` Mode Tests (Stateful, Tool-Aware)

### ✅ C1 — Simple Chat
- [ ] Response contains assistant message
- [ ] Message history preserved in request
- [ ] Role is correct
- [ ] Content is parsed correctly

**Test File:** `spec/ollama/client_chat_spec.rb` or `spec/ollama/client_chat_raw_spec.rb`

**Example Test:**
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

---

### ✅ C2 — Tool-Call Parsing (Critical)
- [ ] `tool_calls` extracted correctly
- [ ] Tool name parsed
- [ ] Arguments parsed as hash
- [ ] **No execution happens** (client must not execute tools)
- [ ] Multiple tool calls handled
- [ ] Tool call ID preserved (if present)

**Test File:** `spec/ollama/client_chat_raw_spec.rb`

**Example Test:**
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

---

### ✅ C3 — Tool Result Round-Trip Formatting
- [ ] Client serializes tool message correctly
- [ ] Ollama accepts tool result message
- [ ] Response parsed cleanly after tool result
- [ ] Tool name preserved
- [ ] Tool content serialized as JSON string

**Test File:** `spec/ollama/client_chat_raw_spec.rb`

**Example Test:**
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

---

## Category C: Protocol Adapters (Anthropic / Native)

### ✅ A1 — Anthropic Message Shape
- [ ] Messages serialized as content blocks
- [ ] Tool calls emitted as `tool_use` (if Anthropic mode)
- [ ] Tool results serialized as `tool_result`
- [ ] Request payload matches Anthropic format

**Test File:** `spec/ollama/client_chat_raw_spec.rb` or new `spec/ollama/protocol_adapter_spec.rb`

**Example Test:**
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

---

### ✅ A2 — Anthropic Response Parsing
- [ ] Client normalizes Anthropic format into internal `tool_calls`
- [ ] Protocol adapter correctness
- [ ] Tool use ID preserved
- [ ] Tool input parsed correctly

**Test File:** `spec/ollama/client_chat_raw_spec.rb` or new `spec/ollama/protocol_adapter_spec.rb`

**Example Test:**
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

---

## Category D: Failure Modes (Non-Negotiable)

### ✅ F1 — Ollama Down
- [ ] Connection refused raises correct exception
- [ ] No hangs
- [ ] Retries handled correctly (if retryable)
- [ ] Error message is clear

**Test File:** `spec/ollama/errors_spec.rb` or `spec/ollama/client_spec.rb`

**Example Test:**
```ruby
it "handles connection refused gracefully" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_raise(Errno::ECONNREFUSED)

  start_time = Time.now
  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::Error)

  # Verify no hangs
  expect(Time.now - start_time).to be < 5
end
```

---

### ✅ F2 — Invalid JSON from Model
- [ ] Client raises parse error
- [ ] Does not silently continue
- [ ] Retries handled (if retryable)
- [ ] Error message includes context

**Test File:** `spec/ollama/errors_spec.rb`

**Example Test:**
```ruby
it "raises error on invalid JSON response" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(status: 200, body: { response: "not json at all" }.to_json)

  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::InvalidJSONError)
end
```

---

### ✅ F3 — Streaming Interruption
- [ ] Partial stream handled
- [ ] Client terminates cleanly
- [ ] No corrupted state
- [ ] Error raised appropriately

**Test File:** `spec/ollama/client_chat_raw_spec.rb` (if streaming tests exist)

**Example Test:**
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

---

## Additional Test Areas

### Retry Logic
- [ ] Retries up to `config.retries` times
- [ ] Only retries retryable errors (5xx, 408, 429)
- [ ] Raises `RetryExhaustedError` after max retries
- [ ] Succeeds if retry succeeds
- [ ] Non-retryable errors (400, 404) fail immediately

### Error Handling
- [ ] **404 (NotFoundError)**: Model not found, no retries, includes suggestions
- [ ] **500 (HTTPError)**: Retryable, retries up to config limit
- [ ] **400 (HTTPError)**: Non-retryable, fails immediately
- [ ] **TimeoutError**: Retries on timeout
- [ ] **InvalidJSONError**: Retries on JSON parse errors
- [ ] **SchemaViolationError**: Retries on schema validation failures
- [ ] **Connection Errors**: Retries on network failures

### Edge Cases
- [ ] JSON wrapped in markdown code blocks
- [ ] Plain JSON responses
- [ ] Empty model lists
- [ ] Missing response fields
- [ ] Malformed JSON
- [ ] Empty prompts
- [ ] Very long prompts
- [ ] Special characters in prompts

### Model Suggestions
- [ ] Suggests similar models on 404
- [ ] Fuzzy matching on model names
- [ ] Limits suggestions to 5 models
- [ ] Handles model listing failures gracefully

---

## What NOT to Test (Agent Concerns)

❌ **Do not test:**
- Infinite loops
- Retries based on content
- Agent stopping behavior
- Tool side effects
- Correctness of answers
- Agent convergence logic
- Policy decisions
- Tool execution
- Agent state management

**Those belong to `agent-runtime` and app repos.**

---

## Test Coverage Goals

- **Transport layer**: 100% coverage
- **Protocol parsing**: 100% coverage
- **Error handling**: 100% coverage
- **Schema validation**: 100% coverage
- **Tool-call parsing**: 100% coverage

**Note:** We don't aim for 100% line coverage of agent logic because agent logic doesn't belong in this gem.

---

## Running the Checklist

1. Review each category
2. Mark tests as complete when implemented
3. Add test file references
4. Update this checklist as new test categories are identified
5. Remove tests that leak agent concerns

---

## Test File Organization

```
spec/
├── ollama/
│   ├── client_spec.rb                    # Basic initialization, config
│   ├── client_generate_spec.rb           # Category A (G1-G3)
│   ├── client_chat_spec.rb               # Category B (C1-C3) - basic chat
│   ├── client_chat_raw_spec.rb           # Category B (C1-C3) - tool calls
│   ├── protocol_adapter_spec.rb          # Category C (A1-A2) - if needed
│   ├── errors_spec.rb                    # Category D (F1-F3)
│   ├── schema_validator_spec.rb          # Category A (G2)
│   ├── client_list_models_spec.rb        # Model listing
│   └── client_model_suggestions_spec.rb   # Model suggestions
```

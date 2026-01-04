# Testing Guide

This document explains how to test the `ollama-client` gem comprehensively.

## Test Structure

The test suite is organized into focused spec files:

- `spec/ollama/client_spec.rb` - Basic client initialization and parameter validation
- `spec/ollama/client_generate_spec.rb` - Comprehensive tests for `generate()` method
- `spec/ollama/client_chat_spec.rb` - Comprehensive tests for `chat()` method
- `spec/ollama/client_list_models_spec.rb` - Tests for `list_models()` method
- `spec/ollama/client_model_suggestions_spec.rb` - Tests for model suggestion feature
- `spec/ollama/errors_spec.rb` - Tests for all error classes
- `spec/ollama/config_spec.rb` - Config class tests (in client_spec.rb)
- `spec/ollama/schema_validator_spec.rb` - Schema validation tests (in client_spec.rb)

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

### Run Specific Test
```bash
bundle exec rspec spec/ollama/client_generate_spec.rb:45
```

### Run Tests Matching a Pattern
```bash
bundle exec rspec -e "retry"
```

## Testing Strategy

### 1. HTTP Mocking with WebMock

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

### 2. Test Coverage Areas

#### ✅ Success Cases
- Successful API calls return parsed JSON
- Schema validation passes
- Config defaults are applied correctly
- Model overrides work
- Options are merged correctly

#### ✅ Error Handling
- **404 (NotFoundError)**: Model not found, no retries, includes suggestions
- **500 (HTTPError)**: Retryable, retries up to config limit
- **400 (HTTPError)**: Non-retryable, fails immediately
- **TimeoutError**: Retries on timeout
- **InvalidJSONError**: Retries on JSON parse errors
- **SchemaViolationError**: Retries on schema validation failures
- **Connection Errors**: Retries on network failures

#### ✅ Retry Logic
- Retries up to `config.retries` times
- Only retries retryable errors (5xx, 408, 429)
- Raises `RetryExhaustedError` after max retries
- Succeeds if retry succeeds

#### ✅ Edge Cases
- JSON wrapped in markdown code blocks
- Plain JSON responses
- Empty model lists
- Missing response fields
- Malformed JSON

#### ✅ Model Suggestions
- Suggests similar models on 404
- Fuzzy matching on model names
- Limits suggestions to 5 models
- Handles model listing failures gracefully

## Writing New Tests

### Basic Test Structure

```ruby
RSpec.describe Ollama::Client, "#method_name" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
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

### Testing Retry Logic

```ruby
it "retries on 500 errors" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(status: 500, body: "Internal Server Error")
    .times(config.retries + 1)

  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::RetryExhaustedError)

  expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate")
    .times(config.retries + 1)
end
```

### Testing Success After Retry

```ruby
it "succeeds on retry" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(
      { status: 500, body: "Internal Server Error" },
      { status: 200, body: { response: '{"test":"value"}' }.to_json }
    )

  result = client.generate(prompt: "test", schema: schema)
  expect(result).to eq("test" => "value")
  expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").twice
end
```

### Testing Error Details

```ruby
it "raises error with correct details" do
  stub_request(:post, "http://localhost:11434/api/generate")
    .to_return(status: 404, body: "Not Found")

  expect do
    client.generate(prompt: "test", schema: schema)
  end.to raise_error(Ollama::NotFoundError) do |error|
    expect(error.requested_model).to eq("test-model")
    expect(error.status_code).to eq(404)
  end
end
```

## Integration Tests (Optional)

For integration tests that hit a real Ollama server, create a separate spec file:

```ruby
# spec/integration/ollama_client_integration_spec.rb
RSpec.describe "Ollama Client Integration", :integration do
  # Skip if OLLAMA_URL is not set
  before(:all) do
    skip "Set OLLAMA_URL environment variable to run integration tests" unless ENV["OLLAMA_URL"]
  end

  let(:client) do
    config = Ollama::Config.new
    config.base_url = ENV["OLLAMA_URL"] || "http://localhost:11434"
    Ollama::Client.new(config: config)
  end

  it "can generate structured output" do
    schema = {
      "type" => "object",
      "required" => ["test"],
      "properties" => { "test" => { "type" => "string" } }
    }

    result = client.generate(
      prompt: "Return a JSON object with test='hello'",
      schema: schema
    )

    expect(result["test"]).to eq("hello")
  end
end
```

Run integration tests separately:
```bash
bundle exec rspec --tag integration
```

## Test Coverage Metrics

To check test coverage, add `simplecov`:

```ruby
# spec/spec_helper.rb
require "simplecov"
SimpleCov.start
```

Then run:
```bash
bundle exec rspec
open coverage/index.html
```

## Continuous Integration

The test suite is designed to run in CI without external dependencies:
- All tests use WebMock (no real Ollama server needed)
- Tests are deterministic and fast
- No flaky network-dependent tests

## Best Practices

1. **Always mock HTTP requests** - Don't make real network calls in unit tests
2. **Test error paths** - Ensure all error scenarios are covered
3. **Test retry logic** - Verify retries work correctly
4. **Test edge cases** - JSON parsing, empty responses, etc.
5. **Keep tests focused** - One assertion per test when possible
6. **Use descriptive test names** - "it 'retries on 500 errors'"
7. **Reset WebMock** - Always reset in `after` blocks

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


# Integration Testing Guide

Integration tests make **actual calls** to a running Ollama server to verify the client works end-to-end with real models.

## Quick Start

```bash
# Run all integration tests (requires Ollama server running)
bundle exec rspec --tag integration

# Run with custom configuration
OLLAMA_URL=http://localhost:11434 \
OLLAMA_MODEL=llama3.1:8b \
bundle exec rspec --tag integration
```

## Prerequisites

1. **Ollama server running** (default: `http://localhost:11434`)
   ```bash
   # Start Ollama server
   ollama serve
   ```

2. **At least one model installed**
   ```bash
   # Install a model
   ollama pull llama3.1:8b
   ```

3. **Optional: Embedding model** (for embedding tests)
   ```bash
   ollama pull nomic-embed-text
   ```

## Test Coverage

Integration tests verify:

### ✅ Core Client Methods
- `#list_models` - Lists available models
- `#generate` - Structured JSON output with schema
- `#generate` - Plain text output without schema
- `#generate` - Complex schemas with enums
- `#chat_raw` - Chat messages and responses
- `#chat_raw` - Conversation history
- `#chat_raw` - Tool calling (if model supports it)

### ✅ Embeddings
- Single text embeddings
- Multiple text embeddings
- Error handling for missing/unsupported models

### ✅ Agent Components
- `Ollama::Agent::Planner` - Planning decisions
- `Ollama::Agent::Executor` - Tool execution loops (if model supports tools)

### ✅ Chat Session
- Session management
- Conversation state
- Message history

### ✅ Error Handling
- `NotFoundError` for non-existent models
- Proper error propagation

## Running Tests

### Run All Integration Tests
```bash
bundle exec rspec --tag integration
```

### Run Specific Test File
```bash
bundle exec rspec spec/integration/ollama_client_integration_spec.rb --tag integration
```

### Run Specific Test
```bash
bundle exec rspec spec/integration/ollama_client_integration_spec.rb:32 --tag integration
```

### With Environment Variables
```bash
# Custom Ollama URL
OLLAMA_URL=http://remote-server:11434 bundle exec rspec --tag integration

# Custom model
OLLAMA_MODEL=llama3.2:3b bundle exec rspec --tag integration

# Custom embedding model
OLLAMA_EMBEDDING_MODEL=nomic-embed-text bundle exec rspec --tag integration

# All together
OLLAMA_URL=http://localhost:11434 \
OLLAMA_MODEL=llama3.1:8b \
OLLAMA_EMBEDDING_MODEL=nomic-embed-text \
bundle exec rspec --tag integration
```

## Test Behavior

### Automatic Skipping
- Tests automatically skip if Ollama server is not available
- Tests skip if required models are not installed
- Tests skip if models don't support certain features (e.g., tool calling)

### Expected Results
- **Passing**: Client correctly communicates with Ollama
- **Pending/Skipped**: Expected when models/features unavailable
- **Failing**: Indicates actual client issues (rare)

## Differences from Unit Tests

| Aspect | Unit Tests | Integration Tests |
|--------|-----------|-------------------|
| **HTTP Calls** | Mocked (WebMock) | Real HTTP calls |
| **Ollama Server** | Not required | Required |
| **Speed** | Fast (~0.1s) | Slower (~15s) |
| **Reliability** | 100% deterministic | Depends on server/model |
| **Coverage** | Transport layer | End-to-end |
| **Run Command** | `bundle exec rspec` | `bundle exec rspec --tag integration` |

## Best Practices

1. **Run unit tests first** - Ensure client code is correct
2. **Run integration tests** - Verify real server communication
3. **Use appropriate models** - Some models support tools, others don't
4. **Handle skips gracefully** - Missing models/features are expected
5. **Check server availability** - Tests skip if Ollama is down

## Troubleshooting

### "Ollama server not available"
- Start Ollama: `ollama serve`
- Check URL: `OLLAMA_URL=http://localhost:11434`
- Verify connection: `curl http://localhost:11434/api/tags`

### "Model not found"
- Install model: `ollama pull llama3.1:8b`
- Set model: `OLLAMA_MODEL=your-model`

### "Empty embedding returned"
- Install embedding model: `ollama pull nomic-embed-text`
- Verify model supports embeddings
- Set model: `OLLAMA_EMBEDDING_MODEL=nomic-embed-text`

### "HTTP 400: Bad Request" (tool calling)
- Some models don't support tool calling
- Test will skip automatically
- Try a different model that supports tools

## CI/CD Integration

Integration tests are **optional** and can be run separately:

```yaml
# Example GitHub Actions
- name: Run Unit Tests
  run: bundle exec rspec

- name: Run Integration Tests (if Ollama available)
  run: bundle exec rspec --tag integration
  if: env.OLLAMA_URL != ''
```

## Summary

Integration tests verify the client works with **real Ollama servers** and **real models**. They complement unit tests by ensuring end-to-end functionality while gracefully handling missing models or unsupported features.

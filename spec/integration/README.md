# Integration Tests

Integration tests make **actual calls** to a running Ollama server to verify the client works end-to-end.

## Prerequisites

1. **Ollama server running** (default: `http://localhost:11434`)
2. **At least one model installed** (e.g., `llama3.1:8b`)
3. **Optional**: Embedding model for embedding tests (e.g., `nomic-embed-text`)

## Running Integration Tests

### Basic Usage

```bash
# Run all integration tests (requires Ollama server)
INTEGRATION=true bundle exec rspec spec/integration/

# Or run all tests including integration
INTEGRATION=true bundle exec rspec
```

### With Custom Configuration

```bash
# Custom Ollama URL
OLLAMA_URL=http://remote-server:11434 INTEGRATION=true bundle exec rspec spec/integration/

# Custom model
OLLAMA_MODEL=llama3.2:3b INTEGRATION=true bundle exec rspec spec/integration/

# Custom embedding model
OLLAMA_EMBEDDING_MODEL=nomic-embed-text INTEGRATION=true bundle exec rspec spec/integration/

# All together
OLLAMA_URL=http://localhost:11434 \
OLLAMA_MODEL=llama3.1:8b \
OLLAMA_EMBEDDING_MODEL=nomic-embed-text \
INTEGRATION=true \
bundle exec rspec spec/integration/
```

## What Gets Tested

- ✅ `#list_models` - Lists available models
- ✅ `#generate` - Structured JSON output with schema
- ✅ `#generate` - Plain text output without schema
- ✅ `#chat_raw` - Chat messages and responses
- ✅ `#chat_raw` - Conversation history
- ✅ `#chat_raw` - Tool calling
- ✅ `#embeddings` - Single and multiple text embeddings
- ✅ `Ollama::Agent::Planner` - Planning decisions
- ✅ `Ollama::Agent::Executor` - Tool execution loops
- ✅ `Ollama::ChatSession` - Session management
- ✅ Error handling with real server

## Skipping Tests

If Ollama server is not available, tests will be automatically skipped with a helpful message.

## CI/CD Behavior

Integration tests are **automatically excluded** from CI/CD pipelines by default:

- **GitHub Actions**: Runs `bundle exec rake` which excludes integration tests unless `INTEGRATION=true`
- **Default behavior**: Integration tests are filtered out unless `INTEGRATION` environment variable is set
- **To enable in CI**: Set `INTEGRATION=true` environment variable

This prevents CI failures when Ollama server is not available in the CI environment.

## Notes

- Integration tests are **separate** from unit tests
- Unit tests use WebMock and don't require Ollama
- Integration tests make **real HTTP calls**
- Integration tests are **slower** than unit tests
- Run unit tests: `bundle exec rspec` or `bundle exec rake` (excludes integration by default)
- Run integration tests: `INTEGRATION=true bundle exec rspec spec/integration/`

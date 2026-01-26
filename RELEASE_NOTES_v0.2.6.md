# Release v0.2.6

## 🎯 Major Changes

### Test Coverage & Quality
- **Increased test coverage from 65.66% to 79.59%**
- Added comprehensive test suites for:
  - `Ollama::DocumentLoader` (file loading, context building)
  - `Ollama::Embeddings` (API calls, error handling)
  - `Ollama::ChatSession` (session management)
  - Tool classes (`Tool`, `Function`, `Parameters`, `Property`)

### Documentation & Examples
- **Reorganized examples**: Moved agent examples to separate repository (`ollama-agent-examples`)
- Kept minimal client-focused examples in this repository
- Rewrote testing documentation to focus on client-only testing (transport/protocol)
- Added test checklist with specific test categories (G1-G3, C1-C3, A1-A2, F1-F3)
- Updated README with enhanced "What This Gem IS NOT" section

### Code Quality
- Fixed all RuboCop offenses
- Improved code quality and consistency
- Aligned workflow with agent-runtime repository

## 📦 Installation

```bash
gem install ollama-client
```

Or add to your Gemfile:

```ruby
gem 'ollama-client', '~> 0.2.6'
```

## 🔗 Links

- [Full Changelog](https://github.com/shubhamtaywade82/ollama-client/blob/main/CHANGELOG.md)
- [Documentation](https://github.com/shubhamtaywade82/ollama-client#readme)
- [Examples Repository](https://github.com/shubhamtaywade82/ollama-agent-examples)

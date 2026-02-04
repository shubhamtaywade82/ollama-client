# New Features Added from ollama-ruby

This document describes the features we've integrated from `ollama-ruby` that align with our **agent-first philosophy**.

## ✅ Features Added

### 1. Embeddings API (`client.embeddings`)

**Purpose**: Enable RAG (Retrieval-Augmented Generation) and semantic search in agents.

**Why it fits**: Agents often need to search knowledge bases, compare documents, and build context from embeddings.

**Usage**:
```ruby
embedding = client.embeddings.embed(model: "all-minilm", input: "What is Ruby?")
```

**Files Added**:
- `lib/ollama/embeddings.rb` - Embeddings API wrapper
- Updated `lib/ollama/client.rb` - Added `embeddings` accessor

### 2. Config Loading from JSON (`Config.load_from_json`)

**Purpose**: Load configuration from JSON files for production deployments.

**Why it fits**: Production agents need configuration management without hardcoding values.

**Usage**:
```ruby
config = Ollama::Config.load_from_json("config.json")
client = Ollama::Client.new(config: config)
```

**Files Modified**:
- `lib/ollama/config.rb` - Added `load_from_json` class method

### 3. Options Class (`Ollama::Options`)

**Purpose**: Type-safe model parameter configuration with validation.

**Why it fits**: Agents need to adjust model behavior dynamically with safety guarantees.

**Usage**:
```ruby
options = Ollama::Options.new(temperature: 0.7, top_p: 0.95)
# Use with chat() - chat() accepts options parameter
client.chat(
  messages: [{ role: "user", content: "..." }],
  format: {...},
  options: options.to_h,
  allow_chat: true
)

# Note: generate() doesn't accept options - use config instead
# config = Ollama::Config.new
# config.temperature = 0.7
# client = Ollama::Client.new(config: config)
```

**Files Added**:
- `lib/ollama/options.rb` - Options class with type checking

### 4. Structured Tool Classes (`Ollama::Tool`, `Tool::Function`, etc.)

**Purpose**: Type-safe, explicit tool schema definitions for agent tools.

**Why it fits**: Production agents need explicit control over tool schemas beyond auto-inference. Enables enum constraints, detailed descriptions, and better documentation.

**Usage**:
```ruby
# Define explicit schema
property = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "City name",
  enum: %w[paris london tokyo]  # Optional enum constraint
)

params = Ollama::Tool::Function::Parameters.new(
  type: "object",
  properties: { city: property },
  required: %w[city]
)

function = Ollama::Tool::Function.new(
  name: "get_weather",
  description: "Get weather for a city",
  parameters: params
)

tool = Ollama::Tool.new(type: "function", function: function)

# Use with Executor (explicit schema + callable)
tools = {
  "get_weather" => {
    tool: tool,
    callable: ->(city:) { { city: city, temp: "22C" } }
  }
}
```

**Files Added**:
- `lib/ollama/dto.rb` - Simplified DTO module (no external dependencies)
- `lib/ollama/tool.rb` - Tool class with DTO support
- `lib/ollama/tool/function.rb` - Function definition with DTO support
- `lib/ollama/tool/function/parameters.rb` - Parameters specification with DTO support
- `lib/ollama/tool/function/parameters/property.rb` - Property definition with DTO support
- Updated `lib/ollama/agent/executor.rb` - Support for explicit Tool objects
- `examples/tool_dto_example.rb` - DTO serialization/deserialization examples

**DTO Features:**
- `to_json` - JSON serialization
- `from_hash` - Deserialization from hash/JSON
- `==` - Equality comparison based on hash representation
- `empty?` - Check if object has no meaningful attributes

All Tool classes include the DTO module, enabling serialization for storage, API responses, and testing.

## 🎯 Design Decisions

### What We Added
- ✅ Features that directly support agent workflows
- ✅ Type safety and validation (Options class)
- ✅ Production deployment needs (JSON config)
- ✅ RAG capabilities (embeddings)

### What We Didn't Add
- ❌ Handler-based architecture (doesn't fit our schema-first approach)
  - See `HANDLERS_ANALYSIS.md` for detailed comparison
  - We use `StreamingObserver` instead for presentation-only streaming
- ❌ Interactive console (not needed for agents)
- ❌ CLI executables (outside our scope)
- ❌ Full API coverage (we focus on agent building blocks)

## 📝 Examples

See `examples/structured_tools.rb` and `examples/tool_dto_example.rb` for complete examples demonstrating:
- Structured tool definitions
- RAG agent with embeddings
- Options usage for fine-tuning

## 🔄 Migration Notes

All new features are **additive** and **backward compatible**:
- Existing code continues to work unchanged
- New features are opt-in
- No breaking changes to existing APIs

## 🚀 Next Steps

These features enable:
1. **RAG Agents**: Build knowledge bases with semantic search
2. **Production Deployments**: JSON-based configuration
3. **Fine-Tuning**: Type-safe model parameter adjustment
4. **Structured Tools**: Explicit tool schemas with enum constraints and validation

All while maintaining our **agent-first philosophy** and **safety guarantees**.

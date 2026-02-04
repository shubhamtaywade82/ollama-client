# Areas for Consideration

This document addresses three key areas that warrant attention in the `ollama-client` codebase.

## ⚠️ 1. Complex Client Class

### Current State

- **File:** `lib/ollama/client.rb`
- **Size:** 860 lines
- **RuboCop Disables:**
  - `Metrics/ClassLength` (entire class)
  - `Metrics/MethodLength` (multiple methods)
  - `Metrics/ParameterLists` (multiple methods)
  - `Metrics/AbcSize` (multiple methods)
  - `Metrics/CyclomaticComplexity` (multiple methods)
  - `Metrics/PerceivedComplexity` (multiple methods)
  - `Metrics/BlockLength` (multiple methods)

### Responsibilities

The `Client` class currently handles:
1. HTTP communication with Ollama API
2. JSON parsing and validation
3. Schema validation
4. Retry logic
5. Error handling and enhancement
6. Tool normalization
7. Response formatting
8. Streaming response parsing
9. Model suggestion logic
10. Response hooks/callbacks

### Recommendations

#### Option A: Extract Service Objects (Recommended)

Break down into focused service classes:

```ruby
# lib/ollama/http_client.rb
class HttpClient
  # Handles all HTTP communication
end

# lib/ollama/response_parser.rb
class ResponseParser
  # Handles JSON parsing, markdown stripping, etc.
end

# lib/ollama/retry_handler.rb
class RetryHandler
  # Handles retry logic and error classification
end

# lib/ollama/client.rb (simplified)
class Client
  def initialize(config: nil)
    @config = config || default_config
    @http_client = HttpClient.new(@config)
    @response_parser = ResponseParser.new
    @retry_handler = RetryHandler.new(@config)
  end
end
```

**Benefits:**
- Single Responsibility Principle
- Easier to test
- Easier to maintain
- Can enable RuboCop metrics

**Trade-offs:**
- More files to navigate
- Slightly more complex initialization

#### Option B: Extract Concerns into Modules

Keep single file but organize with modules:

```ruby
class Client
  include HTTPCommunication
  include ResponseParsing
  include RetryHandling
  include ErrorEnhancement
end
```

**Benefits:**
- Still one file
- Better organization
- Can test modules independently

**Trade-offs:**
- Still a large file
- RuboCop metrics still problematic

#### Option C: Accept Complexity (Current State)

**Rationale:**
- Client is the core API surface
- All methods are public API
- Breaking it up might make usage more complex
- Current structure is functional

**Action Items:**
- Document why metrics are disabled
- Add architectural decision record (ADR)
- Consider refactoring in future major version

### Recommended Approach

**Short-term:** Document the decision (Option C)
**Medium-term:** Extract HTTP client (Option A, partial)
**Long-term:** Full service object extraction (Option A)

---

## ⚠️ 2. Thread Safety

### Current State

**Global Configuration:**
```ruby
module OllamaClient
  @config_mutex = Mutex.new
  
  def self.configure
    @config_mutex.synchronize do
      @config ||= Ollama::Config.new
      yield(@config)
    end
  end
end
```

**Issues:**
1. Mutex protects global config access, but warning says "not thread-safe"
2. Confusing messaging - mutex IS present but warning suggests it's not safe
3. Per-client config is recommended but not enforced

### Analysis

**What's Actually Thread-Safe:**
- ✅ Global config access (protected by mutex)
- ✅ Per-client instances (each has own config)
- ✅ Client methods (stateless, use instance config)

**What's NOT Thread-Safe:**
- ⚠️ Modifying global config while clients are using it
- ⚠️ Shared config objects between threads (if mutated)

### Recommendations

#### Option A: Clarify Documentation (Recommended)

Update warnings to be more accurate:

```ruby
# ⚠️ THREAD SAFETY WARNING:
# Global configuration access is protected by mutex, but modifying
# global config while clients are active can cause race conditions.
# For concurrent agents, prefer per-client configuration:
#
#   config = Ollama::Config.new
#   config.model = "llama3.1"
#   client = Ollama::Client.new(config: config)
```

#### Option B: Make Global Config Immutable

```ruby
def self.configure
  @config_mutex.synchronize do
    @config ||= Ollama::Config.new
    frozen_config = @config.dup.freeze
    yield(frozen_config)
    @config = frozen_config.dup  # Create new instance
  end
end
```

#### Option C: Deprecate Global Config

```ruby
def self.configure
  warn "[DEPRECATED] OllamaClient.configure is deprecated. " \
       "Use per-client config: Ollama::Client.new(config: ...)"
  # ... existing implementation
end
```

### Recommended Approach

**Immediate:** Clarify documentation (Option A)
**Future:** Consider deprecation path (Option C) if usage patterns show global config is rarely needed

---

## ⚠️ 3. Learning Curve

### Current State

The gem provides two agent patterns:

1. **Planner** (`Ollama::Agent::Planner`)
   - Stateless
   - Uses `/api/generate`
   - Returns structured JSON
   - For: routing, classification, decisions

2. **Executor** (`Ollama::Agent::Executor`)
   - Stateful
   - Uses `/api/chat`
   - Tool-calling loops
   - For: multi-step workflows

### Challenges for Beginners

1. **Conceptual Complexity:**
   - Two different patterns (why?)
   - When to use which?
   - Stateless vs stateful concepts

2. **API Surface:**
   - `generate()` vs `chat()` vs `chat_raw()`
   - When to use schema vs plain text
   - Tool calling setup

3. **Documentation:**
   - README is comprehensive but dense
   - Examples are minimal
   - Agent patterns require understanding of concepts

### Recommendations

#### Option A: Enhanced Quick Start Guide

Create a step-by-step guide:

```markdown
# Quick Start Guide

## Step 1: Simple Text Generation
[Example]

## Step 2: Structured Outputs
[Example]

## Step 3: Agent Planning
[Example]

## Step 4: Tool Calling
[Example]
```

#### Option B: Decision Tree / Flowchart

```
Need structured output?
├─ Yes → Use generate() with schema
└─ No → Need conversation?
    ├─ Yes → Use chat_raw() or ChatSession
    └─ No → Use generate() with allow_plain_text: true
```

#### Option C: Simplified Wrapper API

```ruby
# High-level API for beginners
class SimpleAgent
  def initialize(model: "llama3.1:8b")
    @client = Ollama::Client.new
    @model = model
  end
  
  def ask(question, schema: nil)
    if schema
      @client.generate(prompt: question, schema: schema)
    else
      @client.generate(prompt: question, allow_plain_text: true)
    end
  end
end
```

#### Option D: Video Tutorials / Interactive Examples

- Video walkthrough
- Interactive REPL examples
- Common patterns cookbook

### Recommended Approach

**Immediate:**
1. Add "Quick Start" section to README (Option A)
2. Add decision tree diagram (Option B)

**Short-term:**
3. Create `examples/quick_start/` directory with progressive examples
4. Add "Common Patterns" section

**Long-term:**
5. Consider simplified API wrapper (Option C) if demand exists
6. Create video tutorials if community requests

---

## Summary

| Area | Current State | Recommended Action | Priority |
|------|--------------|-------------------|----------|
| **Complex Client** | 860 lines, metrics disabled | Document decision, plan extraction | Medium |
| **Thread Safety** | Mutex present but confusing docs | Clarify documentation | High |
| **Learning Curve** | Comprehensive but dense | Add quick start guide + decision tree | High |

## Next Steps

1. ✅ Create this document (done)
2. Update thread safety documentation
3. Add quick start guide to README
4. Create decision tree diagram
5. Consider ADR for Client class architecture
6. Gather user feedback on learning curve

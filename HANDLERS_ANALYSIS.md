# Handlers Analysis: ollama-ruby vs ollama-client

## Handlers in ollama-ruby

The `ollama-ruby` gem uses a **handler-based architecture** where handlers respond to `to_proc` and return lambda expressions to process responses:

| Handler | Purpose | Use Case |
|---------|---------|----------|
| **Collector** | Collects all responses in an array | Streaming responses |
| **Single** | Returns single response directly | Non-streaming responses |
| **Progress** | Progress bar for create/pull/push | Model management operations |
| **DumpJSON** | Dumps responses as JSON | Debugging/inspection |
| **DumpYAML** | Dumps responses as YAML | Debugging/inspection |
| **Print** | Prints to display | Interactive use |
| **Markdown** | Prints as ANSI markdown | Interactive use |
| **Say** | Text-to-speech output | Accessibility |
| **NOP** | Does nothing | Silent operations |

## Why We Didn't Add Handlers

### 1. **Philosophical Mismatch**

**ollama-ruby approach:**
```ruby
# Handler-based, flexible, general-purpose
ollama.chat(model: 'llama3.1', stream: true, messages: msgs, &Print)
ollama.generate(model: 'llama3.1', prompt: '...', &Markdown)
```

**ollama-client approach:**
```ruby
# Schema-first, contract-based, agent-focused
result = client.generate(prompt: '...', schema: schema)
# Returns validated, structured data directly
```

### 2. **Different Return Semantics**

- **ollama-ruby**: Handlers control what gets returned (could be array, single value, nothing)
- **ollama-client**: Always returns validated, structured data matching the schema

### 3. **State Management**

- **ollama-ruby**: Handlers are stateless processors
- **ollama-client**: We have explicit state (Planner stateless, Executor stateful via messages)

### 4. **Streaming Philosophy**

- **ollama-ruby**: Handlers process streaming chunks (could affect control flow)
- **ollama-client**: Streaming is **presentation-only** via `StreamingObserver` (never affects control flow)

## What We Have Instead

### StreamingObserver (Agent-Focused)

```ruby
observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    print event.text
  when :tool_call_detected
    puts "\n[Tool: #{event.name}]"
  when :state
    puts "State: #{event.state}"
  when :final
    puts "\n--- DONE ---"
  end
end

executor = Ollama::Agent::Executor.new(client, tools: tools, stream: observer)
```

**Key differences:**
- ✅ Explicit event types (`:token`, `:tool_call_detected`, `:state`, `:final`)
- ✅ Never affects control flow (presentation-only)
- ✅ Agent-aware (knows about tool calls, state transitions)
- ✅ Structured events (not raw response chunks)

### Direct Return Values

```ruby
# Always returns validated, structured data
result = client.generate(prompt: '...', schema: schema)
# result is a Hash matching the schema exactly
```

**vs ollama-ruby:**
```ruby
# Handler determines return value
result = ollama.generate(model: '...', prompt: '...', &Collector)
# result could be array, single value, or nil depending on handler
```

## Potential Handler-Like Utilities for Agents

While we don't want the full handler architecture, there might be value in **debugging/development utilities**:

### 1. **Response Debugger** (Useful for Agents)

```ruby
# Could add as a utility, not a handler
module Ollama
  module Debug
    def self.dump_json(response, output: $stdout)
      output.puts JSON.pretty_generate(response)
    end

    def self.dump_yaml(response, output: $stdout)
      require 'yaml'
      output.puts response.to_yaml
    end
  end
end

# Usage:
result = client.generate(prompt: '...', schema: schema)
Ollama::Debug.dump_json(result) if ENV['DEBUG']
```

### 2. **Progress Indicator** (For Long-Running Agent Operations)

```ruby
# Could add for agent workflows that take time
module Ollama
  module Agent
    class ProgressIndicator
      def initialize(total_steps:)
        @total = total_steps
        @current = 0
      end

      def step(message = nil)
        @current += 1
        print "\r[#{@current}/#{@total}] #{message || 'Processing...'}"
        $stdout.flush
      end

      def finish
        puts "\n✓ Complete"
      end
    end
  end
end
```

### 3. **Response Formatter** (For Agent Output)

```ruby
# Could add for pretty-printing agent responses
module Ollama
  module Format
    def self.markdown(text, output: $stdout)
      # Use a markdown library to format
      output.puts text
    end

    def self.structured(data, output: $stdout)
      output.puts JSON.pretty_generate(data)
    end
  end
end
```

## Recommendation

**Don't add handlers** because:
1. ❌ They conflict with our schema-first, contract-based approach
2. ❌ They introduce ambiguity about return values
3. ❌ They don't fit our explicit state management
4. ❌ Our `StreamingObserver` already handles presentation needs

**Do consider** adding **utility modules** for:
1. ✅ Debugging helpers (`Ollama::Debug.dump_json`)
2. ✅ Progress indicators for long agent workflows
3. ✅ Response formatters (if needed for agent output)

These would be **explicit utilities** rather than **handler callbacks**, maintaining our philosophy while providing useful development tools.

## Summary

| Aspect | ollama-ruby Handlers | ollama-client Approach |
|--------|---------------------|------------------------|
| **Architecture** | Handler-based callbacks | Direct return values + StreamingObserver |
| **Return Values** | Handler-dependent | Always validated, structured data |
| **Streaming** | Handler processes chunks | Observer emits events (presentation-only) |
| **State** | Stateless processors | Explicit state (Planner/Executor) |
| **Use Case** | General-purpose, flexible | Agent-focused, contract-based |
| **Debugging** | DumpJSON/DumpYAML handlers | Could add utility modules |

**Conclusion**: Handlers don't fit our agent-first philosophy, but we could add explicit utility modules for debugging/development needs.

# Example Reorganization Proposal

This document proposes how to reorganize examples to keep `ollama-client` focused on the transport layer while providing clear guidance for agent developers.

## Decision: Separate Examples Repository

**Recommendation:** Move all non-trivial examples to a separate repository (`ollama-agent-examples` or similar).

**Rationale:**
- Examples rot faster than APIs
- Agent examples pull in agent-runtime dependencies
- Tool examples imply opinions about tool design
- The client becomes bloated with domain-specific code
- New users confuse client vs agent responsibilities

## What Stays in `ollama-client` Repo

### Minimal Examples (Keep)

These examples demonstrate **client usage only**, not agent behavior:

#### ✅ `examples/basic_generate.rb` (NEW - Create)
**Purpose:** Demonstrate basic `/generate` usage with schema.

**Content:**
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "ollama_client"

client = Ollama::Client.new

schema = {
  "type" => "object",
  "required" => ["status"],
  "properties" => {
    "status" => { "type" => "string" }
  }
}

result = client.generate(
  prompt: "Output a JSON object with a single key 'status' and value 'ok'.",
  schema: schema
)

puts result["status"]  # => "ok"
```

**Why keep:** Minimal, demonstrates core client functionality.

---

#### ✅ `examples/basic_chat.rb` (NEW - Create)
**Purpose:** Demonstrate basic `/chat` usage.

**Content:**
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "ollama_client"

client = Ollama::Client.new

response = client.chat_raw(
  messages: [{ role: "user", content: "Say hello." }],
  allow_chat: true
)

puts response.message.content
```

**Why keep:** Minimal, demonstrates chat API.

---

#### ✅ `examples/tool_calling_parsing.rb` (NEW - Create, or rename existing)
**Purpose:** Demonstrate tool-call **parsing** (not execution).

**Content:**
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "ollama_client"

client = Ollama::Client.new

tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_weather",
    description: "Get weather for a location",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        location: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The city name"
        )
      },
      required: %w[location]
    )
  )
)

response = client.chat_raw(
  messages: [{ role: "user", content: "What's the weather in Paris?" }],
  tools: tool,
  allow_chat: true
)

# Parse tool calls (but don't execute)
if response.message.tool_calls
  response.message.tool_calls.each do |call|
    puts "Tool: #{call['function']['name']}"
    puts "Args: #{JSON.parse(call['function']['arguments'])}"
  end
end
```

**Why keep:** Demonstrates tool-call parsing, not execution.

---

#### ✅ `examples/tool_dto_example.rb` (KEEP - Already minimal)
**Purpose:** Demonstrates Tool DTO serialization.

**Why keep:** Demonstrates client API, not agent behavior.

---

### README Updates

Update `README.md` to include:

1. **Minimal examples inline** (as shown above)
2. **Link to separate examples repo:**
   ```markdown
   ## Full Agent Examples
   
   For complete agent examples (trading agents, coding agents, RAG agents, etc.),
   see: [ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples)
   ```

---

## What Moves to Separate Repository

### Agent Examples (Move)

All examples that demonstrate **agent behavior**, not just client usage:

#### ❌ Move: `examples/dhanhq/` (ENTIRE DIRECTORY)
- `dhanhq/agents/` - Agent implementations
- `dhanhq/analysis/` - Domain-specific analysis
- `dhanhq/builders/` - Domain-specific builders
- `dhanhq/indicators/` - Domain-specific indicators
- `dhanhq/scanners/` - Domain-specific scanners
- `dhanhq/services/` - Domain-specific services
- `dhanhq/utils/` - Domain-specific utilities

**Why move:** Entirely domain-specific, pulls in DhanHQ dependencies, demonstrates agent patterns, not client usage.

---

#### ❌ Move: `examples/dhan_console.rb`
**Why move:** Full agent console with planning, tool execution, domain logic.

---

#### ❌ Move: `examples/dhanhq_agent.rb`
**Why move:** Complete agent implementation.

---

#### ❌ Move: `examples/dhanhq_tools.rb`
**Why move:** Domain-specific tool implementations.

---

#### ❌ Move: `examples/test_dhanhq_tool_calling.rb`
**Why move:** Tests agent behavior, not client parsing.

---

#### ❌ Move: `examples/multi_step_agent_e2e.rb`
**Why move:** Demonstrates agent loops, convergence, state management.

---

#### ❌ Move: `examples/multi_step_agent_with_external_data.rb`
**Why move:** Demonstrates agent workflows with external data.

---

#### ❌ Move: `examples/advanced_multi_step_agent.rb`
**Why move:** Complex agent workflows, not client usage.

---

#### ❌ Move: `examples/advanced_error_handling.rb`
**Why move:** Agent-level error handling patterns, not client error handling.

---

#### ❌ Move: `examples/advanced_edge_cases.rb`
**Why move:** Agent-level edge cases, not client edge cases.

---

#### ❌ Move: `examples/advanced_complex_schemas.rb`
**Why move:** Domain-specific schemas (financial, code review, research), not client schema validation.

---

#### ❌ Move: `examples/advanced_performance_testing.rb`
**Why move:** Agent performance testing, not client performance.

---

#### ❌ Move: `examples/complete_workflow.rb`
**Why move:** Complete agent workflow, not client usage.

---

#### ❌ Move: `examples/chat_console.rb`
**Why move:** Full interactive console, not minimal client demo.

---

#### ❌ Move: `examples/chat_session_example.rb`
**Why move:** Demonstrates ChatSession usage patterns, not core client.

---

#### ❌ Move: `examples/ollama_chat.rb`
**Why move:** Interactive chat demo, not minimal client demo.

---

#### ❌ Move: `examples/personas_example.rb`
**Why move:** Agent persona patterns, not client usage.

---

#### ❌ Move: `examples/structured_outputs_chat.rb`
**Why move:** Agent-level structured output patterns, not client schema validation.

---

#### ❌ Move: `examples/structured_tools.rb`
**Why move:** Agent-level tool organization, not client tool parsing.

---

#### ❌ Move: `examples/test_tool_calling.rb`
**Why move:** Tests tool execution, not client parsing.

---

#### ❌ Move: `examples/tool_calling_direct.rb`
**Why move:** Demonstrates tool execution patterns, not client parsing.

---

#### ❌ Move: `examples/tool_calling_pattern.rb`
**Why move:** Demonstrates agent tool routing patterns, not client parsing.

---

#### ❌ Move: `examples/ollama-api.md`
**Why move:** Documentation, not example code.

---

## Proposed Separate Repository Structure

```
ollama-agent-examples/
├── README.md
│   └── Links back to ollama-client, explains this is for agent examples
├── basic/
│   ├── simple_tool_calling.rb
│   ├── multi_step_agent.rb
│   └── chat_session.rb
├── trading/
│   ├── dhanhq/
│   │   ├── agents/
│   │   ├── analysis/
│   │   ├── scanners/
│   │   └── ...
│   └── README.md
├── coding/
│   ├── code_review_agent.rb
│   └── refactoring_agent.rb
├── rag/
│   ├── document_qa.rb
│   └── semantic_search.rb
├── advanced/
│   ├── multi_step_workflows.rb
│   ├── error_handling_patterns.rb
│   └── performance_testing.rb
└── tools/
    ├── structured_tools.rb
    └── tool_routing_patterns.rb
```

---

## Migration Plan

### Phase 1: Create Minimal Examples
1. Create `examples/basic_generate.rb`
2. Create `examples/basic_chat.rb`
3. Create `examples/tool_calling_parsing.rb` (or rename existing minimal one)
4. Keep `examples/tool_dto_example.rb`

### Phase 2: Update README
1. Add inline minimal examples to README
2. Add link to separate examples repo (create placeholder if needed)
3. Add "What this gem is NOT" section

### Phase 3: Create Separate Repository
1. Create `ollama-agent-examples` repository
2. Move all agent examples
3. Update README in examples repo to link back to `ollama-client`
4. Update `ollama-client` README to link to examples repo

### Phase 4: Clean Up
1. Remove moved examples from `ollama-client`
2. Update `examples/README.md` to reflect minimal examples only
3. Update any documentation that references moved examples

---

## Benefits of This Separation

### For `ollama-client`:
- ✅ Stays focused on transport layer
- ✅ Examples don't rot as quickly
- ✅ No domain-specific dependencies
- ✅ Clearer boundaries for contributors
- ✅ Easier to maintain

### For Agent Developers:
- ✅ Examples can be opinionated
- ✅ Can include agent-runtime dependencies
- ✅ Can demonstrate real-world patterns
- ✅ Can evolve independently
- ✅ Clear separation of concerns

### For Users:
- ✅ Don't confuse client vs agent
- ✅ Clear learning path
- ✅ Can find examples relevant to their domain
- ✅ Client stays stable while examples evolve

---

## README Section to Add

Add this section to `README.md`:

```markdown
## 🚫 What This Gem IS NOT

This gem is **NOT**:
- ❌ A chatbot UI framework
- ❌ A domain-specific agent implementation
- ❌ A tool execution engine
- ❌ A memory store
- ❌ A promise of full Ollama API coverage (focuses on agent workflows)

**Domain tools and application logic live outside this gem.**

## 📚 Examples

### Minimal Examples (In This Repo)

See `examples/` for minimal client usage examples:
- `basic_generate.rb` - Basic `/generate` usage
- `basic_chat.rb` - Basic `/chat` usage
- `tool_calling_parsing.rb` - Tool-call parsing (no execution)
- `tool_dto_example.rb` - Tool DTO serialization

### Full Agent Examples (Separate Repo)

For complete agent examples (trading agents, coding agents, RAG agents, multi-step workflows, etc.),
see: [ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples)

This separation keeps `ollama-client` focused on the transport layer while providing
comprehensive examples for agent developers.
```

---

## Summary

**Keep in `ollama-client`:**
- ✅ `examples/basic_generate.rb` (create)
- ✅ `examples/basic_chat.rb` (create)
- ✅ `examples/tool_calling_parsing.rb` (create or rename)
- ✅ `examples/tool_dto_example.rb` (keep)

**Move to `ollama-agent-examples`:**
- ❌ Everything else in `examples/`

**Update:**
- ✅ `README.md` - Add minimal examples inline, link to separate repo
- ✅ `examples/README.md` - Reflect minimal examples only

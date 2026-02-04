# Ollama::Client

> An **agent-first Ruby client for Ollama**, optimized for **deterministic planners** and **safe tool-using executors**.

This is **NOT** a chatbot UI,
**NOT** domain-specific,
**NOT** a general-purpose “everything Ollama supports” wrapper.

This gem provides:

* ✅ Safe LLM calls
* ✅ Strict output contracts
* ✅ Retry & timeout handling
* ✅ Explicit state (Planner is stateless; Executor is intentionally stateful via `messages`)
* ✅ Extensible schemas

Domain tools and application logic live **outside** this gem. For convenience, it includes a small `Ollama::Agent` layer (Planner + Executor) that encodes correct agent usage.

## 🎯 What This Gem IS

* LLM call executor
* Output validator
* Retry + timeout manager
* Schema enforcer
* A minimal agent layer (`Ollama::Agent::Planner` + `Ollama::Agent::Executor`)

## 🚫 What This Gem IS NOT

This gem is **NOT**:
* ❌ A chatbot UI framework
* ❌ A domain-specific agent implementation
* ❌ A tool execution engine
* ❌ A memory store
* ❌ A promise of full Ollama API coverage (focuses on agent workflows)
* ❌ An agent runtime (it provides transport + protocol, not agent logic)

**Domain tools and application logic live outside this gem.**

This keeps it **clean and future-proof**.

## 🔒 Guarantees

| Guarantee                                | Yes |
| ---------------------------------------- | --- |
| Client requests are explicit             | ✅   |
| Planner is stateless (no hidden memory)  | ✅   |
| Executor is stateful (explicit messages) | ✅   |
| Retry bounded                            | ✅   |
| Schema validated (when schema provided)  | ✅   |
| Tools run in Ruby (not in the LLM)       | ✅   |
| Streaming is display-only (Executor)     | ✅   |

**Non-negotiable safety rule:** the **LLM never executes side effects**. It may request a tool call; **your Ruby code** executes the tool.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ollama-client"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ollama-client
```

## Quick Start

### Step 1: Simple Text Generation

```ruby
require "ollama_client"

client = Ollama::Client.new

# Get plain text response (no schema = plain text)
response = client.generate(
  prompt: "Explain Ruby blocks in one sentence"
)

puts response
# => "Ruby blocks are anonymous functions passed to methods..."
```

### Step 2: Structured Outputs (Recommended for Agents)

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define JSON schema
schema = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "calculate", "finish"] },
    "reasoning" => { "type" => "string" }
  }
}

# Get structured decision
result = client.generate(
  prompt: "User wants weather in Paris. What should I do?",
  schema: schema
)

puts result["action"]      # => "search"
puts result["reasoning"]    # => "Need to fetch weather data..."
```

### Step 3: Agent Planning (Stateless)

```ruby
require "ollama_client"

client = Ollama::Client.new
planner = Ollama::Agent::Planner.new(client)

decision_schema = {
  "type" => "object",
  "required" => ["action"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "calculate", "finish"] }
  }
}

plan = planner.run(
  prompt: "Decide the next action",
  schema: decision_schema
)

# Use the structured decision
case plan["action"]
when "search"
  # Execute search
when "calculate"
  # Execute calculation
when "finish"
  # Task complete
end
```

### Step 4: Tool Calling (Stateful)

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define tools
tools = {
  "get_weather" => ->(city:) { { city: city, temp: 22, condition: "sunny" } }
}

executor = Ollama::Agent::Executor.new(client, tools: tools)

answer = executor.run(
  system: "You are a helpful assistant. Use tools when needed.",
  user: "What's the weather in Paris?"
)

puts answer
# => "The weather in Paris is 22°C and sunny."
```

**Next Steps:** See [Choosing the Correct API](#choosing-the-correct-api-generate-vs-chat) below for guidance on when to use each method.

## Usage

**Note:** You can use `require "ollama_client"` (recommended) or `require "ollama/client"` directly. The client works with or without the global `OllamaClient` configuration module.

### Primary API: `generate()`

**`generate(prompt:, schema: nil, model: nil, strict: false, return_meta: false)`** is the **primary and recommended method** for agent-grade usage:

- ✅ Stateless, explicit state injection
- ✅ Uses `/api/generate` endpoint
- ✅ Ideal for: agent planning, tool routing, one-shot analysis, classification, extraction
- ✅ No implicit memory or conversation history
- ✅ Supports both structured JSON (with schema) and plain text/markdown (without schema)

**This is the method you should use for hybrid agents.**

**Usage:**
- **With schema** (structured JSON): `generate(prompt: "...", schema: {...})` - returns Hash
- **Without schema** (plain text): `generate(prompt: "...")` - returns String (plain text/markdown)

### Choosing the Correct API (generate vs chat)

**Decision Tree:**

```
Need structured JSON output?
├─ Yes → Use generate() with schema
│   └─ Need conversation history?
│       ├─ No → Use generate() directly
│       └─ Yes → Include context in prompt (generate() is stateless)
│
└─ No → Need plain text/markdown?
    ├─ Yes → Use generate() without schema
    │   └─ Need conversation history?
    │       ├─ No → Use generate() directly
    │       └─ Yes → Include context in prompt
    │
    └─ Need tool calling?
        ├─ Yes → Use Executor (chat API with tools)
        │   └─ Multi-step workflow with tool loops
        │
        └─ No → Use ChatSession (chat API for UI)
            └─ Human-facing chat interface
```

**Quick Reference:**

| Use Case | Method | API Endpoint | State |
|----------|--------|--------------|-------|
| Agent planning/routing | `generate()` | `/api/generate` | Stateless |
| Structured extraction | `generate()` | `/api/generate` | Stateless |
| Simple text generation | `generate()` | `/api/generate` | Stateless |
| Tool-calling loops | `Executor` | `/api/chat` | Stateful |
| UI chat interface | `ChatSession` | `/api/chat` | Stateful |

**Detailed Guidance:**

- **Use `/api/generate`** (via `Ollama::Client#generate` or `Ollama::Agent::Planner`) for **stateless planner/router** steps where you want strict, deterministic structured outputs.
- **Use `/api/chat`** (via `Ollama::Agent::Executor`) for **stateful tool-using** workflows where the model may request tool calls across multiple turns.

**Warnings:**
- Don't use `generate()` for tool-calling loops (you'll end up re-implementing message/tool lifecycles).
- Don't use `chat()` for deterministic planners unless you're intentionally managing conversation state.
- Don't let streaming output drive decisions (streaming is presentation-only).

### Providing Context to Queries

You can provide context to your queries in several ways:

**Option 1: Include context directly in the prompt (generate)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Build prompt with context
context = "User's previous actions: search, calculate, validate"
user_query = "What should I do next?"

full_prompt = "Given this context: #{context}\n\nUser asks: #{user_query}"

result = client.generate(
  prompt: full_prompt,
  schema: {
    "type" => "object",
    "required" => ["action"],
    "properties" => {
      "action" => { "type" => "string" }
    }
  }
)
```

**Option 2: Use system messages (chat/chat_raw)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Provide context via system message
context = "You are analyzing market data. Current market status: Bullish. Key indicators: RSI 65, MACD positive."

response = client.chat_raw(
  messages: [
    { role: "system", content: context },
    { role: "user", content: "What's the next trading action?" }
  ],
  allow_chat: true
)

puts response.message.content
```

**Option 3: Use Planner with context parameter**

```ruby
require "ollama_client"

client = Ollama::Client.new
planner = Ollama::Agent::Planner.new(client)

context = {
  previous_actions: ["search", "calculate"],
  user_preferences: "prefers conservative strategies"
}

plan = planner.run(
  prompt: "Decide the next action",
  context: context
)
```

**Option 4: Load documents from directory (DocumentLoader)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Load all documents from a directory (supports .txt, .md, .csv, .json)
loader = Ollama::DocumentLoader.new("docs/")
loader.load_all  # Loads all supported files

# Get all documents as context
context = loader.to_context

# Use in your query
result = client.generate(
  prompt: "Context from documents:\n#{context}\n\nQuestion: What is Ruby?",
  schema: {
    "type" => "object",
    "required" => ["answer"],
    "properties" => {
      "answer" => { "type" => "string" }
    }
  }
)

# Or load specific files
loader.load_file("ruby_guide.md")
ruby_context = loader["ruby_guide.md"]

result = client.generate(
  prompt: "Based on this documentation:\n#{ruby_context}\n\nExplain Ruby's key features."
)
```

**Option 5: RAG-style context injection (using embeddings + DocumentLoader)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# 1. Load documents
loader = Ollama::DocumentLoader.new("docs/")
loader.load_all

# 2. When querying, find relevant context using embeddings
query = "What is Ruby?"
# (In real RAG, you'd compute embeddings and find similar docs)

# 3. Inject relevant context into prompt
relevant_context = loader["ruby_guide.md"]  # Or find via similarity search

result = client.generate(
  prompt: "Context: #{relevant_context}\n\nQuestion: #{query}\n\nAnswer based on the context:"
)
```

**Option 5: Multi-turn conversation with accumulated context**

```ruby
require "ollama_client"

client = Ollama::Client.new

messages = [
  { role: "system", content: "You are a helpful assistant with access to context." },
  { role: "user", content: "What is Ruby?" }
]

# First response
response1 = client.chat_raw(messages: messages, allow_chat: true)
puts response1.message.content

# Add context and continue conversation
messages << { role: "assistant", content: response1.message.content }
messages << { role: "user", content: "Tell me more about its use cases" }

response2 = client.chat_raw(messages: messages, allow_chat: true)
puts response2.message.content
```

### Plain Text / Markdown Responses (No JSON Schema)

For simple text or markdown responses without JSON validation, you can use either `generate()` or `chat_raw()`:

**Option 1: Using `generate()` (recommended for simple queries)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Get plain text/markdown response (omit schema for plain text)
text_response = client.generate(
  prompt: "Explain Ruby in simple terms"
)

puts text_response
# Output: Plain text or markdown explanation (String)
```

**Option 2: Using `chat_raw()` (for multi-turn conversations)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Get plain text/markdown response (no format required)
response = client.chat_raw(
  messages: [{ role: "user", content: "Explain Ruby in simple terms" }],
  allow_chat: true
)

# Access the plain text content
text_response = response.message.content
puts text_response
# Output: Plain text or markdown explanation
```

**When to use which:**
- **`generate()` without schema** - Simple one-shot queries, explanations, text generation (returns plain text)
- **`generate()` with schema** - Structured JSON outputs for agents (recommended for agents)
- **`chat_raw()` without format** - Multi-turn conversations with plain text
- **`chat_raw()` with format** - Multi-turn conversations with structured outputs

### Scope / endpoint coverage

This gem intentionally focuses on **agent building blocks**:

- **Supported**: `/api/generate`, `/api/chat`, `/api/tags`, `/api/ping`, `/api/embed`
- **Not guaranteed**: full endpoint parity with every Ollama release (advanced model mgmt, etc.)

### Agent endpoint mapping (unambiguous)

Within `Ollama::Agent`:

- `Ollama::Agent::Planner` **always** uses `/api/generate`
- `Ollama::Agent::Executor` **always** uses `/api/chat`

(`Ollama::Client` remains the low-level API surface.)

### Planner Agent (stateless, /api/generate)

```ruby
require "ollama_client"

client = Ollama::Client.new

# Option 1: With schema (recommended for structured outputs)
DECISION_SCHEMA = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["search", "calculate", "store", "retrieve", "finish"]
    },
    "reasoning" => {
      "type" => "string"
    }
  }
}

planner = Ollama::Agent::Planner.new(client)

plan = planner.run(
  prompt: "Given the user request, decide the next action.",
  schema: DECISION_SCHEMA,
  context: { user_request: "Plan a weekend trip to Rome" }
)

puts plan["action"]      # => "search" (or one of the enum values)
puts plan["reasoning"]    # => Explanation string
```

**Option 2: Without schema (returns any JSON)**

```ruby
require "ollama_client"

client = Ollama::Client.new
planner = Ollama::Agent::Planner.new(client)

plan = planner.run(
  prompt: <<~PROMPT,
    Given the user request, output a JSON plan with steps.
    Return ONLY valid JSON.
  PROMPT
  context: { user_request: "Plan a weekend trip to Rome" }
)

puts plan  # => Any valid JSON structure
```

### Executor Agent (tool loop, /api/chat)

**Simple approach (auto-inferred schemas):**

```ruby
require "ollama_client"
require "json"

client = Ollama::Client.new

tools = {
  "fetch_weather" => ->(city:) { { city: city, forecast: "sunny", high_c: 18, low_c: 10 } },
  "find_hotels" => ->(city:, max_price:) { [{ name: "Hotel Example", city: city, price_per_night: max_price }] }
}

executor = Ollama::Agent::Executor.new(client, tools: tools)

answer = executor.run(
  system: "You are a travel assistant. Use tools when you need real data.",
  user: "Plan a 3-day trip to Paris in October. Use tools for weather and hotels."
)

puts answer
```

**Structured approach (explicit schemas with Tool classes):**

```ruby
require "ollama_client"

# Define explicit tool schema
location_prop = Ollama::Tool::Function::Parameters::Property.new(
  type: "string",
  description: "The city name"
)

params = Ollama::Tool::Function::Parameters.new(
  type: "object",
  properties: { city: location_prop },
  required: %w[city]
)

function = Ollama::Tool::Function.new(
  name: "fetch_weather",
  description: "Get weather for a city",
  parameters: params
)

tool = Ollama::Tool.new(type: "function", function: function)

# Associate tool schema with callable
tools = {
  "fetch_weather" => {
    tool: tool,
    callable: ->(city:) { { city: city, forecast: "sunny" } }
  }
}

executor = Ollama::Agent::Executor.new(client, tools: tools)
```

Use structured tools when you need:
- Explicit control over parameter types and descriptions
- Enum constraints on parameters
- Better documentation for complex tools
- Serialization/deserialization (JSON storage, API responses)

**DTO (Data Transfer Object) functionality:**

All Tool classes support serialization and deserialization:

```ruby
# Create a tool
tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "fetch_weather",
    description: "Get weather for a city",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        city: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The city name"
        )
      },
      required: %w[city]
    )
  )
)

# Serialize to JSON
json = tool.to_json

# Deserialize from hash
tool2 = Ollama::Tool.from_hash(JSON.parse(json))

# Equality comparison
tool == tool2  # Compares hash representations (returns true)

# Empty check
params = Ollama::Tool::Function::Parameters.new(type: "object", properties: {})
params.empty?  # True if no properties/required fields
```

See `examples/tool_dto_example.rb` for complete DTO usage examples.

### Streaming (Executor only; presentation-only)

Streaming is treated as **presentation**, not control. The agent buffers the full assistant message and only
executes tools after the streamed message is complete and parsed.

**Streaming format support:**
- The streaming parser accepts **NDJSON** (one JSON object per line).
- It also tolerates **SSE-style** lines prefixed with `data: ` (common in proxies), as long as the payload is JSON.

```ruby
observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    print event.text
  when :tool_call_detected
    puts "\n[Tool requested: #{event.name}]"
  when :final
    puts "\n--- DONE ---"
  end
end

executor = Ollama::Agent::Executor.new(client, tools: tools, stream: observer)
```

### JSON & schema contracts (including “no extra fields”)

This gem is contract-first:

- **JSON parsing**: invalid JSON raises `Ollama::InvalidJSONError` (no silent fallback to text).
- **Schema validation**: invalid outputs raise `Ollama::SchemaViolationError`.
- **No extra fields by default**: object schemas are treated as strict shapes unless you explicitly allow more fields.
  - To allow extras, set `"additionalProperties" => true` on the relevant object schema.

**Strictness control:** methods accept `strict:` to fail fast (no retries on invalid JSON/schema) vs retry within configured bounds.

### Basic Configuration

```ruby
require "ollama_client"

# Configure global defaults
OllamaClient.configure do |c|
  c.base_url = "http://localhost:11434"
  c.model = "llama3.1"
  c.timeout = 30
  c.retries = 3
  c.temperature = 0.2
end
```

### Quick Start Pattern

**Option 1: Plain text/markdown (no schema)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Simple text response - no schema needed
response = client.generate(
  prompt: "Explain Ruby programming in one sentence"
)

puts response
# Output: Plain text explanation
```

**Option 2: Structured JSON (with schema)**

```ruby
require "ollama_client"

client = Ollama::Client.new

# 1. Define your JSON schema
schema = {
  "type" => "object",
  "required" => ["field1", "field2"],
  "properties" => {
    "field1" => { "type" => "string" },
    "field2" => { "type" => "number" }
  }
}

# 2. Call the LLM with your schema
begin
  result = client.generate(
    model: "llama3.1:8b",
    prompt: "Return a JSON object with field1 as a string and field2 as a number. Example: field1 could be 'example' and field2 could be 42.",
    schema: schema
  )

  # 3. Use the validated structured output
  puts result["field1"]
  puts result["field2"]

  # The result is guaranteed to match your schema!

rescue Ollama::SchemaViolationError => e
  # Handle validation errors (rare with format parameter)
  puts "Invalid response: #{e.message}"
rescue Ollama::Error => e
  # Handle other errors
  puts "Error: #{e.message}"
end
```

### Example: Planning Agent (Complete Workflow)

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define the schema for decision-making
decision_schema = {
  "type" => "object",
  "required" => ["action", "reasoning", "confidence"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["search", "calculate", "finish"],
      "description" => "The action to take: 'search', 'calculate', or 'finish'"
    },
    "reasoning" => {
      "type" => "string",
      "description" => "Why this action was chosen"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level in this decision"
    },
    "parameters" => {
      "type" => "object",
      "description" => "Parameters needed for the action"
    }
  }
}

# Get structured decision from LLM
begin
  result = client.generate(
    prompt: "Analyze the current situation and decide the next step. Context: User asked about weather in Paris.",
    schema: decision_schema
  )

  # Use the structured output
  puts "Action: #{result['action']}"
  puts "Reasoning: #{result['reasoning']}"
  puts "Confidence: #{(result['confidence'] * 100).round}%"

  # Route based on action
  case result["action"]
  when "search"
    # Execute search with parameters
    query = result.dig("parameters", "query") || "default query"
    puts "Executing search: #{query}"
    # ... your search logic here
  when "calculate"
    # Execute calculation
    puts "Executing calculation with params: #{result['parameters']}"
    # ... your calculation logic here
  when "finish"
    puts "Task complete!"
  else
    puts "Unknown action: #{result['action']}"
  end

rescue Ollama::SchemaViolationError => e
  puts "LLM returned invalid structure: #{e.message}"
  # Handle gracefully - maybe retry or use fallback
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end
```

**Note:** The gem uses Ollama's native `format` parameter for structured outputs, which enforces the JSON schema server-side. This ensures reliable, consistent JSON responses that match your schema exactly.

### Advanced: When (Rarely) to Use `chat()`

⚠️ **Warning:** `chat()` is **NOT recommended** for agent planning or tool routing.

**Safety gate:** `chat()` requires explicit opt-in (`allow_chat: true`) so you don’t accidentally use it inside agent internals.

**Why?**
- Chat encourages implicit memory and conversation history
- Message history grows silently over time
- Schema validation becomes weaker with accumulated context
- Harder to reason about state in agent systems

**When to use `chat()`:**
- User-facing chat interfaces (not agent internals)
- Explicit multi-turn conversations where you control message history
- When you need conversation context for a specific use case

**For agents, prefer `generate()` with explicit state injection:**

```ruby
# Define decision schema
decision_schema = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => { "type" => "string" },
    "reasoning" => { "type" => "string" }
  }
}

# ✅ GOOD: Explicit state in prompt
actions = ["search", "calculate", "validate"]
context = "Previous actions: #{actions.join(', ')}"
result = client.generate(
  prompt: "Given context: #{context}. Decide next action.",
  schema: decision_schema
)

# ❌ AVOID: Implicit conversation history
messages = [{ role: "user", content: "Decide the next action based on previous actions: search, calculate, validate" }]
result = client.chat(messages: messages, format: decision_schema, allow_chat: true)

# Problem: History grows silently - you must manually manage it
messages << { role: "assistant", content: result.to_json }
messages << { role: "user", content: "Now do the next step" }
result2 = client.chat(messages: messages, format: decision_schema, allow_chat: true)
# messages.size is now 3, and will keep growing with each turn
# You must manually track what's in the history
# Schema validation can become weaker with accumulated context
# Harder to reason about state in agent systems
```

### Decision Table: `generate()` vs `chat()` vs `ChatSession`

> **Use `generate()` for systems. Use `chat()` or `ChatSession` for humans.**

| Use Case | Method | Schema Guarantees | Streaming | Memory | When to Use |
|----------|--------|-------------------|-----------|--------|-------------|
| **Agent planning/routing** | `generate()` | ✅ Strong | ❌ No | ❌ Stateless | Default for agents |
| **Structured extraction** | `generate()` | ✅ Strong | ❌ No | ❌ Stateless | Data extraction, classification |
| **Tool-calling loops** | `chat_raw()` | ⚠️ Weaker | ✅ Yes | ✅ Stateful | Executor agent internals |
| **UI chat interface** | `ChatSession` | ⚠️ Best-effort | ✅ Yes | ✅ Stateful | Human-facing assistants |
| **Multi-turn conversations** | `ChatSession` | ⚠️ Best-effort | ✅ Yes | ✅ Stateful | Interactive chat |

**Core Rule:** Chat must be a feature flag, not default behavior.

### Using `ChatSession` for Human-Facing Chat

For UI assistants and interactive chat, use `ChatSession` to manage conversation state:

```ruby
require "ollama_client"

# Enable chat in config
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true

client = Ollama::Client.new(config: config)

# Create streaming observer for presentation
observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    print event.text
  when :final
    puts "\n--- DONE ---"
  end
end

# Create chat session with system message
chat = Ollama::ChatSession.new(
  client,
  system: "You are a helpful assistant",
  stream: observer
)

# Send messages (history is managed automatically)
chat.say("Hello")
chat.say("Explain Ruby blocks")

# Clear history if needed (keeps system message)
chat.clear
```

**Important:** Schema validation in chat is **best-effort** for formatting, not correctness. Never use chat+schema for agent control flow.

### Example: Chat API (Advanced Use Case)

```ruby
require "ollama_client"
require "json"

client = Ollama::Client.new

# Define schema for friend list
friend_list_schema = {
  "type" => "object",
  "required" => ["friends"],
  "properties" => {
    "friends" => {
      "type" => "array",
      "items" => {
        "type" => "object",
        "required" => ["name", "age", "is_available"],
        "properties" => {
          "name" => { "type" => "string" },
          "age" => { "type" => "integer" },
          "is_available" => { "type" => "boolean" }
        }
      }
    }
  }
}

# Use chat API with messages (for user-facing interfaces, not agent internals)
messages = [
  {
    role: "user",
    content: "I have two friends. The first is Ollama 22 years old busy saving the world, and the second is Alonso 23 years old and wants to hang out. Return a list of friends in JSON format"
  }
]

begin
  response = client.chat(
    model: "llama3.1:8b",
    messages: messages,
    format: friend_list_schema,
    allow_chat: true,
    options: {
      temperature: 0  # More deterministic
    }
  )

  # Response is already parsed and validated
  response["friends"].each do |friend|
    status = friend["is_available"] ? "available" : "busy"
    puts "#{friend['name']} (#{friend['age']}) - #{status}"
  end

rescue Ollama::SchemaViolationError => e
  puts "Response didn't match schema: #{e.message}"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end
```

### Example: Tool Calling (Direct API Usage)

For tool calling, use `chat_raw()` to access `tool_calls` from the response:

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define tool using Tool classes
tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_current_weather",
    description: "Get the current weather for a location",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        location: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The location to get the weather for, e.g. San Francisco, CA"
        ),
        temperature_unit: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "The unit to return the temperature in",
          enum: %w[celsius fahrenheit]
        )
      },
      required: %w[location temperature_unit]
    )
  )
)

# Create message
message = Ollama::Agent::Messages.user("What is the weather today in Paris?")

# Use chat_raw() to get full response with tool_calls
response = client.chat_raw(
  model: "llama3.1:8b",
  messages: [message],
  tools: tool,  # Pass Tool object directly (or array of Tool objects)
  allow_chat: true
)

# Access tool_calls from response
tool_calls = response.dig("message", "tool_calls")
if tool_calls && !tool_calls.empty?
  tool_calls.each do |call|
    name = call.dig("function", "name")
    args = call.dig("function", "arguments")
    puts "Tool: #{name}, Args: #{args}"
  end
end
```

**Note:**
- `chat()` returns only the content (for simple use cases)
- `chat_raw()` returns the full response with `message.tool_calls` (for tool calling)
- Both methods accept `tools:` parameter (Tool object, array of Tool objects, or array of hashes)
- For agent tool loops, use `Ollama::Agent::Executor` instead (handles tool execution automatically)

### MCP support (local and remote servers)

You can connect to [Model Context Protocol](https://modelcontextprotocol.io) (MCP) servers and use their tools with the Executor.

**Remote MCP server (HTTP URL, e.g. [GitMCP](https://gitmcp.io)):**

```ruby
require "ollama_client"

client = Ollama::Client.new

# Remote MCP server URL (e.g. GitMCP: https://gitmcp.io/owner/repo)
mcp_client = Ollama::MCP::HttpClient.new(
  url: "https://gitmcp.io/shubhamtaywade82/agent-runtime",
  timeout_seconds: 60
)

bridge = Ollama::MCP::ToolsBridge.new(client: mcp_client)
tools = bridge.tools_for_executor

executor = Ollama::Agent::Executor.new(client, tools: tools)
answer = executor.run(
  system: "You have access to the agent-runtime docs. Use tools when the user asks about the repo.",
  user: "What does this repo do?"
)

puts answer
mcp_client.close
```

**Local MCP server (stdio, e.g. filesystem server):**

```ruby
# Local MCP server via stdio (requires Node.js/npx)
mcp_client = Ollama::MCP::StdioClient.new(
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
  timeout_seconds: 60
)

bridge = Ollama::MCP::ToolsBridge.new(stdio_client: mcp_client)  # or client: mcp_client
tools = bridge.tools_for_executor
# ... same executor usage
mcp_client.close
```

- **Stdio**: `Ollama::MCP::StdioClient` — spawns a subprocess; use for local servers (e.g. `npx @modelcontextprotocol/server-filesystem`).
- **HTTP**: `Ollama::MCP::HttpClient` — POSTs JSON-RPC to a URL; use for remote servers (e.g. [gitmcp.io/owner/repo](https://gitmcp.io)).
- **Bridge**: `Ollama::MCP::ToolsBridge.new(client: mcp_client)` or `stdio_client: mcp_client`; then `tools_for_executor` for the Executor.
- No extra gem; implementation is self-contained.
- See [examples/mcp_executor.rb](examples/mcp_executor.rb) (stdio) and [examples/mcp_http_executor.rb](examples/mcp_http_executor.rb) (URL).

### Example: Data Analysis with Validation

```ruby
require "ollama_client"

client = Ollama::Client.new

analysis_schema = {
  "type" => "object",
  "required" => ["summary", "confidence", "key_points"],
  "properties" => {
    "summary" => { "type" => "string" },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1
    },
    "key_points" => {
      "type" => "array",
      "items" => { "type" => "string" },
      "minItems" => 1,
      "maxItems" => 5
    },
    "sentiment" => {
      "type" => "string",
      "enum" => ["positive", "neutral", "negative"]
    }
  }
}

data = "Sales increased 25% this quarter, customer satisfaction is at 4.8/5"

begin
  result = client.generate(
    prompt: "Analyze this data: #{data}. Return confidence as a decimal between 0 and 1 (e.g., 0.85 for 85% confidence).",
    schema: analysis_schema
  )

  # Use the validated structured output
  puts "Summary: #{result['summary']}"
  puts "Confidence: #{(result['confidence'] * 100).round}%"
  puts "Sentiment: #{result['sentiment']}"
  puts "\nKey Points:"
  result["key_points"].each_with_index do |point, i|
    puts "  #{i + 1}. #{point}"
  end

  # Make decisions based on structured data
  if result["confidence"] > 0.8 && result["sentiment"] == "positive"
    puts "\n✅ High confidence positive analysis - proceed with action"
  elsif result["confidence"] < 0.5
    puts "\n⚠️ Low confidence - review manually"
  end

rescue Ollama::SchemaViolationError => e
  puts "Analysis failed validation: #{e.message}"
  puts "The LLM response didn't match the schema constraints."
  # Could retry with a clearer prompt or use fallback logic
rescue Ollama::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end
```

### Custom Configuration Per Client

**Important:** For production agents, prefer per-client configuration over global config to avoid thread-safety issues.

```ruby
require "ollama_client"

# Prefer per-client config for agents (thread-safe)
custom_config = Ollama::Config.new
custom_config.model = "qwen2.5:14b"
custom_config.temperature = 0.1
custom_config.timeout = 60  # Increase timeout for complex schemas

client = Ollama::Client.new(config: custom_config)
```

**Note:** Global `OllamaClient.configure` is convenient for defaults, but is **not thread-safe by default**. For concurrent agents, use per-client configuration.

**Timeout Tips:**
- Default timeout is 20 seconds
- For complex schemas or large prompts, increase to 60-120 seconds
- For simple schemas, 20 seconds is usually sufficient
- Timeout applies per request (not total workflow time)

### Listing Available Models

```ruby
require "ollama_client"

client = Ollama::Client.new
models = client.list_models
puts "Available models: #{models.join(', ')}"
```

### Loading Documents from Directory (DocumentLoader)

Load files from a directory and use them as context for your queries. Supports `.txt`, `.md`, `.csv`, and `.json` files:

```ruby
require "ollama_client"

client = Ollama::Client.new

# Load all documents from a directory
loader = Ollama::DocumentLoader.new("docs/")
loader.load_all  # Loads all .txt, .md, .csv, .json files

# Get all documents as a single context string
context = loader.to_context

# Use in your query
result = client.generate(
  prompt: "Context from documents:\n#{context}\n\nQuestion: What is Ruby?",
  schema: {
    "type" => "object",
    "required" => ["answer"],
    "properties" => {
      "answer" => { "type" => "string" }
    }
  }
)

# Load specific file
ruby_guide = loader.load_file("ruby_guide.md")

# Access loaded documents
all_files = loader.files  # ["ruby_guide.md", "python_intro.txt", ...]
specific_doc = loader["ruby_guide.md"]

# Load recursively from subdirectories
loader.load_all(recursive: true)

# Select documents by pattern
ruby_docs = loader.select(/ruby/)
```

**Supported file types:**
- **`.txt`** - Plain text files
- **`.md`, `.markdown`** - Markdown files
- **`.csv`** - CSV files (converted to readable text format)
- **`.json`** - JSON files (pretty-printed)

**Example directory structure:**
```
docs/
  ├── ruby_guide.md
  ├── python_intro.txt
  ├── data.csv
  └── config.json
```

### Embeddings for RAG/Semantic Search

Use embeddings for building knowledge bases and semantic search in agents:

```ruby
require "ollama_client"

client = Ollama::Client.new

# Note: You need an embedding model installed in Ollama
# Common models: nomic-embed-text, all-minilm, mxbai-embed-large
# Check available models: client.list_models
# The client uses /api/embed endpoint internally

begin
  # Single text embedding
  # Note: Model name can be with or without tag (e.g., "nomic-embed-text" or "nomic-embed-text:latest")
  embedding = client.embeddings.embed(
    model: "nomic-embed-text",  # Use an available embedding model
    input: "What is Ruby programming?"
  )
  # Returns: [0.123, -0.456, ...] (array of floats)
  # For nomic-embed-text, dimension is typically 768
  puts "Embedding dimension: #{embedding.length}"
  puts "First few values: #{embedding.first(5).map { |v| v.round(4) }}"

  # Multiple texts
  embeddings = client.embeddings.embed(
    model: "nomic-embed-text",
    input: ["What is Ruby?", "What is Python?", "What is JavaScript?"]
  )
  # Returns: [[...], [...], [...]] (array of embedding arrays)
  # Each inner array is an embedding vector for the corresponding input text
  puts "Number of embeddings: #{embeddings.length}"
  puts "Each embedding dimension: #{embeddings.first.length}"

rescue Ollama::NotFoundError => e
  puts "Model not found. Install an embedding model first:"
  puts "  ollama pull nomic-embed-text"
  puts "Or check available models: client.list_models"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
  # Error message includes helpful troubleshooting steps
end

# Use for semantic similarity in agents
def cosine_similarity(vec1, vec2)
  dot_product = vec1.zip(vec2).sum { |a, b| a * b }
  magnitude1 = Math.sqrt(vec1.sum { |x| x * x })
  magnitude2 = Math.sqrt(vec2.sum { |x| x * x })
  dot_product / (magnitude1 * magnitude2)
end

def find_similar(query_embedding, document_embeddings, threshold: 0.7)
  document_embeddings.select do |doc_emb|
    cosine_similarity(query_embedding, doc_emb) > threshold
  end
end
```

### Configuration from JSON

Load configuration from JSON files for production deployments:

```ruby
require "ollama_client"
require "json"

# Create config.json file (or use an existing one)
config_data = {
  "base_url" => "http://localhost:11434",
  "model" => "llama3.1:8b",
  "timeout" => 30,
  "retries" => 3,
  "temperature" => 0.2
}

# Write config file
File.write("config.json", JSON.pretty_generate(config_data))

# Load configuration from file
begin
  config = Ollama::Config.load_from_json("config.json")
  client = Ollama::Client.new(config: config)
  puts "Client configured from config.json"
rescue Ollama::Error => e
  puts "Error loading config: #{e.message}"
end
```

### Type-Safe Model Options

Use the `Options` class for type-checked model parameters:

```ruby
require "ollama_client"

client = Ollama::Client.new

# Define schema
analysis_schema = {
  "type" => "object",
  "required" => ["summary"],
  "properties" => {
    "summary" => { "type" => "string" }
  }
}

# Options with validation
options = Ollama::Options.new(
  temperature: 0.7,
  top_p: 0.95,
  top_k: 40,
  num_ctx: 4096,
  seed: 42
)

# Will raise ArgumentError if values are out of range
# options.temperature = 3.0  # Error: temperature must be between 0.0 and 2.0

# Use with chat() - chat() accepts options parameter
client.chat(
  messages: [{ role: "user", content: "Analyze this data" }],
  format: analysis_schema,
  options: options.to_h,
  allow_chat: true
)

# Note: generate() doesn't accept options parameter
# For generate(), set options in config instead:
# config = Ollama::Config.new
# config.temperature = 0.7
# client = Ollama::Client.new(config: config)
```

### Error Handling

```ruby
require "ollama_client"

client = Ollama::Client.new
schema = {
  "type" => "object",
  "required" => ["result"],
  "properties" => {
    "result" => { "type" => "string" }
  }
}

begin
  result = client.generate(
    prompt: "Return a simple result",
    schema: schema
  )
  # Success - use the result
  puts "Result: #{result['result']}"
rescue Ollama::NotFoundError => e
  # 404 Not Found - model or endpoint doesn't exist
  # The error message automatically suggests similar model names if available
  puts e.message
  # Example output:
  # HTTP 404: Not Found
  #
  # Model 'qwen2.5:7b' not found. Did you mean one of these?
  #   - qwen2.5:14b
  #   - qwen2.5:32b
rescue Ollama::HTTPError => e
  # Other HTTP errors (400, 500, etc.)
  # Non-retryable errors (400) are raised immediately
  # Retryable errors (500, 503, 408, 429) are retried
  puts "HTTP #{e.status_code}: #{e.message}"
rescue Ollama::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Ollama::SchemaViolationError => e
  puts "Output didn't match schema: #{e.message}"
rescue Ollama::RetryExhaustedError => e
  puts "Failed after retries: #{e.message}"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end
```

## Architecture: Tool Calling Pattern

**Important:** This gem includes a tool-calling *loop helper* (`Ollama::Agent::Executor`), but it still does **not** include any domain tools. Tool execution remains **pure Ruby** and **outside the LLM**.

### Why Tools Still Don’t “Belong in the LLM”

Tool execution is an **orchestration concern**, not an LLM concern. The correct pattern is:

```
┌──────────────────────────┐
│   Your Agent / App       │
│                          │
│  ┌──────── Tool Router ┐ │
│  │                    │ │
│  │  ┌─ Ollama Client ┐│ │  ← This gem (reasoning only)
│  │  │ (outputs intent)││ │
│  │  └────────────────┘│ │
│  │        ↓            │ │
│  │   Tool Registry     │ │  ← Your code
│  │        ↓            │ │
│  │   Tool Executor     │ │  ← Your code
│  └────────────────────┘ │
└──────────────────────────┘
```

### The Correct Pattern

1. **LLM requests a tool call** (via `/api/chat` + tool definitions)
2. **Your agent executes the tool deterministically** (pure Ruby, no LLM calls)
3. **Tool result is appended as `role: "tool"`**
4. **LLM continues** until no more tool calls

**Key principle:** LLMs describe intent. Agents execute tools.

### Example: Tool-Aware Agent

```ruby
# In your agent code (NOT in this gem)
class ToolRouter
  def initialize(llm:, registry:)
    @llm = llm  # Ollama::Client instance
    @registry = registry
  end

  def step(prompt:, context:)
    # LLM outputs intent (not execution)
    decision = @llm.generate(
      prompt: prompt,
      schema: {
        "type" => "object",
        "required" => ["action"],
        "properties" => {
          "action" => { "type" => "string" },
          "input" => { "type" => "object" }
        }
      }
    )

    return { done: true } if decision["action"] == "finish"

    # Agent executes tool (deterministic)
    tool = @registry.fetch(decision["action"])
    output = tool.call(input: decision["input"], context: context)

    { tool: tool.name, output: output }
  end
end
```

This keeps the `ollama-client` gem **domain-agnostic** and **reusable** across any project.

**See the [ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples) repository for working implementations of this pattern.**

## 📚 Examples

### Minimal Examples (In This Repo)

The `examples/` directory contains minimal examples demonstrating **client usage only**:

- **`basic_generate.rb`** - Basic `/generate` usage with schema validation
- **`basic_chat.rb`** - Basic `/chat` usage
- **`tool_calling_parsing.rb`** - Tool-call parsing (no execution)
- **`tool_dto_example.rb`** - Tool DTO serialization

These examples focus on **transport and protocol correctness**, not agent behavior.

### Full Agent Examples (Separate Repository)

For complete agent examples (trading agents, coding agents, RAG agents, multi-step workflows, tool execution patterns, etc.), see:

**[ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples)**

This separation keeps `ollama-client` focused on the transport layer while providing comprehensive examples for agent developers.

**Why this separation?**
- Examples rot faster than APIs
- Agent examples pull in domain-specific dependencies
- Tool examples imply opinions about tool design
- The client stays clean and maintainable
- Users don't confuse client vs agent responsibilities

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update `lib/ollama/version.rb` and `CHANGELOG.md`, then commit. You can:

- Run `bundle exec rake release` locally to create the tag, push commits/tags, and publish to [rubygems.org](https://rubygems.org).
- Push a tag `vX.Y.Z` to trigger the GitHub Actions release workflow, which builds and publishes the gem using the `RUBYGEMS_API_KEY` secret.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shubhamtaywade82/ollama-client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ollama::Client project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

# Ollama::Client

A **low-level, opinionated Ollama client** for **LLM-based hybrid agents**,
**NOT** a chatbot,
**NOT** domain-specific,
**NOT** a framework.

This gem provides:

* ✅ Safe LLM calls
* ✅ Strict output contracts
* ✅ Retry & timeout handling
* ✅ Zero hidden state
* ✅ Extensible schemas

Everything else (tools, agents, domains) lives **outside** this gem.

## 🎯 What This Gem IS

* LLM call executor
* Output validator
* Retry + timeout manager
* Schema enforcer

## 🚫 What This Gem IS NOT

* ❌ Agent loop
* ❌ Tool router
* ❌ Domain logic
* ❌ Memory store
* ❌ Chat UI

This keeps it **clean and future-proof**.

## 🔒 Guarantees

| Guarantee              | Yes |
| ---------------------- | --- |
| Stateless              | ✅   |
| Retry bounded          | ✅   |
| Schema validated       | ✅   |
| Deterministic defaults | ✅   |
| Agent-safe             | ✅   |
| Domain-agnostic        | ✅   |

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

## Usage

**Note:** You can use `require "ollama_client"` (recommended) or `require "ollama/client"` directly. The client works with or without the global `OllamaClient` configuration module.

### Primary API: `generate()`

**`generate(prompt:, schema:)`** is the **primary and recommended method** for agent-grade usage:

- ✅ Stateless, explicit state injection
- ✅ Uses `/api/generate` endpoint
- ✅ Ideal for: agent planning, tool routing, one-shot analysis, classification, extraction
- ✅ No implicit memory or conversation history

**This is the method you should use for hybrid agents.**

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

The basic pattern for using structured outputs:

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
    prompt: "Your prompt here",
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
# ✅ GOOD: Explicit state in prompt
context = "Previous actions: #{actions.join(', ')}"
result = client.generate(
  prompt: "Given context: #{context}. Decide next action.",
  schema: decision_schema
)

# ❌ AVOID: Implicit conversation history
messages = [{ role: "user", content: "..." }]
result = client.chat(messages: messages, format: schema)  # History grows silently
```

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
    prompt: "Analyze this data: #{data}",
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
  # Could retry or use fallback logic
rescue Ollama::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Ollama::Error => e
  puts "Error: #{e.message}"
end
```

### Custom Configuration Per Client

```ruby
require "ollama_client"

custom_config = Ollama::Config.new
custom_config.model = "qwen2.5:14b"
custom_config.temperature = 0.1

client = Ollama::Client.new(config: custom_config)
```

### Listing Available Models

```ruby
require "ollama_client"

client = Ollama::Client.new
models = client.list_models
puts "Available models: #{models.join(', ')}"
```

### Error Handling

```ruby
require "ollama_client"

begin
  result = client.generate(prompt: prompt, schema: schema)
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

**Important:** This gem does **NOT** include tool calling. Here's why and how to do it correctly:

### Why Tools Don't Belong Here

Ollama does not have native tool calling. Tool execution is an **orchestration concern**, not an LLM concern. The correct pattern is:

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

1. **LLM outputs structured intent** (via this gem with schema validation)
2. **Agent validates and routes** to the appropriate tool
3. **Tool executes deterministically** (pure Ruby, no LLM calls)
4. **Agent observes results** and decides next step

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shubhamtaywade82/ollama-client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ollama::Client project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

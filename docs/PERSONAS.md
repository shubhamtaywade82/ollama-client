# Personas: Explicit Personalization for Ollama

## Core Principle

**You cannot "install" ChatGPT-style personalization into Ollama globally.** You **inject it explicitly** at the **system / prompt layer**, and you do it **deliberately**, depending on whether you are:

- doing **schema-based agent work**, or
- doing **chat / streaming UI work**.

This is by design — and it's actually a *good thing*.

## Mental Model

### ChatGPT Personalization
- Stored server-side
- Implicit
- Always applied
- You don't control when it's used

### Ollama (local / Docker)
- **No implicit memory**
- **No global personality**
- Everything must be **explicitly provided**
- You decide *when* it applies

So your customization becomes a **tool**, not a background bias. That's architecturally superior.

## Where Personalization Lives

There are **exactly three valid places** to apply your personalization:

| Context                 | How              | When                 |
| ----------------------- | ---------------- | -------------------- |
| **Planner / generate**  | Prompt prefix    | Deterministic agents |
| **Chat / UI assistant** | `system` message | Human-facing chat    |
| **Executor tool loop**  | System guard     | Controlled reasoning |

You do **NOT** bake it into:
- the model
- Docker image
- Ollama server config

## Using Personas

### 1. Planner (Schema-Based Agent Work)

Use **compressed agent-safe personas** for deterministic structured outputs:

```ruby
require "ollama_client"

client = Ollama::Client.new

planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

plan = planner.run(
  prompt: "Design a caching layer for a high-traffic API.",
  schema: DECISION_SCHEMA
)
```

✅ This preserves determinism
✅ No chatty behavior
✅ No markdown drift

### 2. Executor (Tool-Calling Agents)

Use **compressed agent-safe personas** for tool-calling agents:

```ruby
executor = Ollama::Agent::Executor.new(client, tools: tools)

answer = executor.run(
  system: Ollama::Personas.get(:trading, variant: :agent),
  user: "Analyze AAPL. Get current price and technical indicators."
)
```

### 3. ChatSession (Human-Facing Chat)

Use **minimal chat-safe personas** for human-facing chat interfaces:

```ruby
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true

client = Ollama::Client.new(config: config)

observer = Ollama::StreamingObserver.new do |event|
  print event.text if event.type == :token
end

chat = Ollama::ChatSession.new(
  client,
  system: Ollama::Personas.get(:architect, variant: :chat),
  stream: observer
)

chat.say("How should I structure a multi-agent system?")
```

Chat-safe personas:
- Allow explanations and examples (chat needs)
- Allow streaming (presentation needs)
- Still prevent hallucination (safety)
- Explicitly disclaim authority (boundaries)
- Never imply side effects (safety)

Now:
- Streaming works
- Tone matches your architect persona
- UI feels consistent
- Agents are unaffected

## Available Personas

### Architect
- **Agent variant**: Minimal, focused on correctness and invariants
- **Chat variant**: Minimal chat-safe, allows explanations while preventing hallucination
- **Use case**: System design, architecture decisions, planning

### Trading
- **Agent variant**: Minimal, data-driven analysis
- **Chat variant**: Minimal chat-safe, allows explanations while preventing hallucination
- **Use case**: Market analysis, trading decisions, risk management

### Reviewer
- **Agent variant**: Minimal, focused on maintainability
- **Chat variant**: Minimal chat-safe, allows explanations while preventing hallucination
- **Use case**: Code review, refactoring, quality assurance

## Agent-Safe vs Chat-Safe Personas

### Agent-Safe Personas (`:agent` variant)

Designed for `/api/generate` with JSON schemas:

- **Minimal and directive** - reduces token noise and drift
- **Non-chatty** - avoids markdown and verbosity
- **Schema-first** - protects deterministic parsing
- **No persona fluff** - no tone bleed into output
- **Preserves determinism** - for planners, routers, decision engines

**Use with:**
- `Planner` for structured outputs
- `generate()` with schemas
- Tool routing and decision making

**Will NOT fight:**
- Schema enforcement
- Retries
- Validation
- Tool routing
- Policy gates

### Chat-Safe Personas (`:chat` variant)

Designed for `/api/chat` with ChatSession:

- **Allows explanations** - chat needs context
- **Allows streaming** - presentation needs
- **Still prevents hallucination** - safety first
- **Explicitly disclaims authority** - clear boundaries
- **Never implies side effects** - safety boundaries

**Use with:**
- `ChatSession` for human-facing interfaces
- Streaming conversations
- Explanatory interactions

**Must NEVER be used for:**
- Schema-based agent work
- `/api/generate` calls
- Deterministic structured outputs

## Critical Separation

**Agent personas** (`:agent`):
- `/api/generate` + schemas = deterministic reasoning
- Use for planners, routers, decision engines
- Preserves determinism and schema enforcement

**Chat personas** (`:chat`):
- `/api/chat` + humans = explanatory conversation
- Use for ChatSession, streaming, UI interactions
- Allows explanations while maintaining safety

**NEVER mix them:**
- Using chat personas in agents breaks determinism
- Using agent personas in chat suppresses explanations
- They serve different purposes with different contracts

## Persona Registry

```ruby
# List all available personas
Ollama::Personas.available
# => [:architect, :trading, :reviewer]

# Check if persona exists
Ollama::Personas.exists?(:architect)
# => true

# Get persona (defaults to :agent variant)
Ollama::Personas.get(:architect)
Ollama::Personas.get(:architect, variant: :agent)
Ollama::Personas.get(:architect, variant: :chat)
```

## Dynamic Persona Selection

```ruby
def select_persona_for_task(task_type)
  case task_type
  when :planning, :architecture
    Ollama::Personas.get(:architect, variant: :agent)
  when :trading, :analysis
    Ollama::Personas.get(:trading, variant: :agent)
  when :review, :refactor
    Ollama::Personas.get(:reviewer, variant: :agent)
  else
    nil
  end
end

planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: select_persona_for_task(:planning)
)
```

## Per-Call Persona Override

```ruby
planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

# Override for specific call
plan = planner.run(
  prompt: "Review this code for maintainability issues.",
  schema: REVIEW_SCHEMA,
  system_prompt: Ollama::Personas.get(:reviewer, variant: :agent)
)
```

## Why NOT Bake Into Docker / Model

You might be tempted to:
- create a custom Modelfile
- bake instructions into the model
- hardcode personality in the server

**Don't.** Here's why:

❌ All agents inherit it (bad)
❌ Hard to change per task
❌ Breaks determinism
❌ Makes debugging impossible
❌ Pollutes structured outputs

Your personalization is **contextual**, not universal.

## Multiple Personas (This is Powerful)

Once explicit, you can do this:

```ruby
PERSONAS = {
  architect: Ollama::Personas.get(:architect, variant: :agent),
  trading: Ollama::Personas.get(:trading, variant: :agent),
  reviewer: Ollama::Personas.get(:reviewer, variant: :agent)
}

# Choose per call
prompt = PERSONAS[:architect] + task_prompt
```

This is **far more powerful** than ChatGPT's single global personality.

## Philosophy Alignment

Your instruction says:

> "Treat LLMs as components, not oracles"

That **forces** explicit prompting. Implicit personalization would actually violate your own design principles.

## Validation Checklist

### For Agent Personas

If the model:
- ✅ Emits pure JSON matching schema exactly → correct usage
- ✅ No markdown or explanations → correct usage
- ✅ Deterministic outputs → correct usage
- ❌ Emits markdown → prompt is being misused
- ❌ Adds extra fields → schema too loose or prompt issue
- ❌ Explains decisions → prompt leaked into chat mode
- ❌ Hallucinates APIs → tool boundaries not enforced

### For Chat Personas

If the model:
- ✅ Explains reasoning when helpful → correct usage
- ✅ Uses markdown for readability → correct usage
- ✅ Disclaims authority explicitly → correct usage
- ✅ No side effects implied → correct usage
- ❌ Executes actions → boundaries not clear
- ❌ Invents data/APIs → hallucination prevention failed
- ❌ Makes guarantees → safety boundaries not enforced

## What NOT to Do

### ❌ Don't Use Chat Personas for Agent Work

```ruby
# WRONG - breaks determinism
planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :chat)  # ❌
)

plan = planner.run(prompt: "...", schema: SCHEMA)
# This will fight schema enforcement and break determinism
```

### ❌ Don't Use Agent Personas for Chat

```ruby
# WRONG - suppresses explanations
chat = Ollama::ChatSession.new(
  client,
  system: Ollama::Personas.get(:architect, variant: :agent)  # ❌
)
# This makes chat feel robotic and suppresses helpful explanations
```

### ❌ Don't Mix Personas

```ruby
# WRONG - creates confusion
prompt = Ollama::Personas.get(:architect, variant: :agent) +
         Ollama::Personas.get(:architect, variant: :chat)
# This creates conflicting instructions
```

### ✅ Do Keep Them Separate

```ruby
# CORRECT - explicit separation
agent_persona = Ollama::Personas.get(:architect, variant: :agent)
chat_persona = Ollama::Personas.get(:architect, variant: :chat)

# Use agent persona for planning
planner = Ollama::Agent::Planner.new(client, system_prompt: agent_persona)

# Use chat persona for UI
chat = Ollama::ChatSession.new(client, system: chat_persona)
```

## Summary

**Q:** How do I use this customization with Ollama / Docker / ollama-client?
**A:**

- You **do NOT install it into Ollama**
- You **inject it as a system prompt**
- You **use minimal agent-safe version for agents** (`/api/generate` + schemas)
- You **use minimal chat-safe version for chat UIs** (`/api/chat` + ChatSession)
- You **never make it implicit**
- You **never mix agent and chat personas**

That's not a limitation. That's **correct system design**.

## Examples

See `examples/personas_example.rb` for complete working examples.

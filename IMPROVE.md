# Improve `ollama-client` — Planning Document

## Scope

This plan improves the **developer experience and ecosystem reach** of `ollama-client`.
No Ruby code changes are included here — this is the **roadmap only**.

**Source docs:**

- `../improve-ollama-systems.md`
- `../improve-ollama-systems-structured.md`
- `../ollama-ecosystem.md`

**Ground-truth codebase anchors:**

- `ollama-client.gemspec` → gem identity, dependencies, shipped files
- `CLAUDE.md` → stack, architecture, public API contract rules
- `API_CONTRACT.md` → stable method signatures, error hierarchy, recovery behavior
- `ARCHITECTURE.md` → declared non-goals and boundary rule
- `lib/ollama/client.rb` → top-level entry point and mixin structure
- `lib/ollama/client/*.rb` → per-endpoint behavior modules
- `lib/ollama/transport/*.rb` → existing transport boundary
- `lib/ollama/openai_compat.rb` → existing isolated OpenAI-compat facade

The current gem already contains significant architecture: transport boundary, typed responses, schema validation, retry/repair policies, streaming observer hooks, multi-key failover, model profiles, and an explicit public API contract. The plan below treats those as **fixed preconditions** and layers on top of them.

---

## Strategic Pivot

**From:** "An agent-first Ruby client for Ollama"
**To:** "The production-safe, contract-driven Ruby AI SDK for Ollama — trusted in Rails, agents, CLIs, and production services."

The new identity must cover every segment the source docs identify:

- Rails AI features
- CLIs and scripts
- Chatbots
- AI agents / autonomous systems
- Workflow engines
- Embeddings and RAG pipelines
- Structured-output consumers
- MCP servers
- Evaluation pipelines

The umbrella term is **Ruby AI SDK**. Agents are *one* consumer of the SDK, not the target market.

---

## Phased Roadmap

### Phase 0 — Positioning and Messaging (0–1 week)

**Goal:** communicate the right value before writing new code.

| Task | Notes |
|---|---|
| Rewrite `gemspec.summary` and `gemspec.description` | Replace "agent-first / Rails & agent systems" wording |
| Rewrite `README.md` lead section | New one-line positioning; include user segments explicitly |
| Add "Why this gem exists" table | Keep current production-guarantee content, expand audience |
| Update `CHANGELOG.md` | Mark next milestone as positioning-only (no code/API change) |

---

### Phase 1 — Ruby-Native Request Ergonomics (weeks 1–3)

**Goal:** reduce hash boilerplate without breaking any existing signature.

All additions are additive. `messages: [...]` hash API stays stable forever.

#### 1.1 `Ollama::Messages` builder

```ruby
messages = Ollama::Messages.new
messages.system("You are a senior Ruby engineer.")
messages.user("Review this code.", attachment: Ollama::Attachment.file("lib.rb"))
messages.assistant("Sure — loading the code.")
messages.image("What is in this screenshot?", file: "ui.png")
```

- `.to_h` returns the hash that `chat()` already accepts today.
- No change to any `client.chat` parameter list.

#### 1.2 `Ollama::Attachment` types

```ruby
Ollama::Attachment.file("paris.txt")
Ollama::Attachment.base64(encoded)
Ollama::Attachment.url("https://...")
```

- Each `.to_h` produces the exact `:image` / URL shape expected by the Ollama API.

#### 1.3 `Ollama::Prompt` DSL (optional)

```ruby
class ExplainCode < Ollama::Prompt
  input :code, :language

  system <<~PROMPT
    You are...
  PROMPT

  user do
    code
    "Please review."
  end
end
```

- `.messages` returns an `Ollama::Messages` instance.
- `.to_h` returns the hash for the final endpoint call.
- Pure convenience; `client.chat(messages: [...])` is unchanged.

---

### Phase 2 — Tool and Schema DSLs (weeks 3–5)

**Goal:** eliminate raw tool-hash and JSON-schema hand-authoring.

#### 2.1 `Ollama::Tool` DSL

```ruby
class WeatherTool < Ollama::Tool
  description "Get current weather for a city"

  input do
    string :city, description: "The name of the city"
    string :unit, optional: true, default: "celsius"
  end

  output do
    number :temperature
    string :condition
  end

  def call(city:, unit:)
    { temperature: 23, condition: "Sunny" }
  end
end
```

- `.to_h` produces the same tool hash documented in `API_CONTRACT.md`.
- Works with the existing `chat(tools:, ...)` call.
- Class-level DSL exposes `.name` and `.schema` for serializers/introspection.

#### 2.2 `Ollama::Schema` DSL

```ruby
class TradeSignal
  include Ollama::Schema

  string :direction, enum: %w[buy sell wait]
  number :confidence, minimum: 0, maximum: 1
  number :stop_loss
end
```

- `.to_h` produces JSON Schema (`{ type: "object", required: [...], properties: {...} }`).
- Passed to the existing `generate(schema: TradeSignal.to_h)` or `chat(format: TradeSignal.to_h)` paths.
- Cleaner than the current hand-authored `{ type: "object", properties: { ... } }` hash.

#### 2.3 Relationship to current code

- `lib/ollama/schema_validator.rb` and `lib/ollama/tool/*.rb` already validate and parse tool data.
- The DSLs provide a friendlier source for the same hashes, without changing validation behavior.

---

### Phase 3 — Streaming as Ruby IO (weeks 5–6)

**Goal:** make streaming idiomatic while keeping existing hooks as the contract.

Current stable behavior (from `API_CONTRACT.md`):

- `hooks: { on_token:, on_thought:, ... }` — observer-only, unlocks streaming automatically
- `GenerateStreamHandler.call` — advanced internal streamer

Additive change:

#### 3.1 Enumerable chat response

```ruby
stream = client.chat(messages: [...], stream: true)
stream.each do |chunk|
  print chunk.content
end
```

- `chunk` exposes `#content`, `#thinking`, `#tool_calls?`, `#done?`.
- Under the hood still uses the existing `GenerateStreamHandler` behavior.
- `hooks:` are unchanged and remain the advanced escape hatch for `on_thought:` and `on_tool_call:`.
- This is a Ruby-surface convenience layered on the same NDJSON plumbing.

---

### Phase 4 — Middleware Pipeline Formalization (weeks 6–8)

**Goal:** turn existing behaviors into an official composable middleware API.

Current situation: retry, repair, auto-pull, multi-key failover, and transport adapters already exist internally. The missing piece is a **shared public surface** for registering and composing them.

#### 4.1 `Ollama::Middleware` namespace

Shared minimalist interface:

```ruby
module Ollama
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(request)
      @app.call(request)
    end
  end
end
```

- Matches the blueprint’s Rack/Faraday moment exactly.
- Mirrors the existing `transport/` adapter contract.

#### 4.2 Promote built-ins into middleware

Each current behavior becomes a middleware class in `lib/ollama/middleware/`:

- `retry.rb`
- `json_repair.rb`
- `schema_repair.rb`
- `auto_pull.rb`
- `rate_limiter.rb`
- `logger.rb`
- `model_capability_guard.rb`

#### 4.3 Client registration

```ruby
config = Ollama::Config.new
config.middleware.use Retry
config.middleware.use Logger.new($stderr)
client = Ollama::Client.new(config: config)
```

- **Backwards-compatible default:** an internal stack ships with all current behaviors pre-registered. Only users who manipulate `config.middleware` get a different stack.
- No change to any `client.chat/generate` signature.
- `API_CONTRACT.md` stays intact — the public contract remains at the method level, while the middleware stack is the new implementation detail.
- This leverages the existing `transport/` boundary, which is already the “terminal middleware.”

#### 4.4 Capability-aware guard

The blueprint’s `CapabilityValidation` policy maps cleanly onto existing `ModelProfile` code:

- Before dispatch: check requested features against `profile.capabilities`.
- Fail fast with a typed error (already covered by the present error hierarchy).

---

### Phase 5 — Testing and Compliance (week 8)

**Goal:** make the SDK trivial to test and protect new transports against regressions.

#### 5.1 `Ollama::Testing` helpers

Build on the existing `transport/mock.rb`:

```ruby
include Ollama::Testing

stub_chat(content: "Hello, World!")
stub_generate(schema: TradeSignal.to_h, content: '{ "direction": "buy" }')
stub_stream(chunks: ["data: {}", "data: [DONE]"])
stub_error(Ollama::TimeoutError)
```

- Each helper enqueues a preconfigured mock transport response.
- Keeps tests deterministic — no live Ollama needed.

#### 5.2 `spec/compliance/` shared examples

| File | Contract asserted |
|---|---|
| `chat_compliance_spec.rb` | `client.chat(messages:)` returns `Ollama::Response` shape |
| `generate_compliance_spec.rb` | `client.generate(prompt:)` string/schema behavior |
| `streaming_compliance_spec.rb` | `hooks:` semantics and enumerable stream shape |
| `tool_calling_compliance_spec.rb` | tool hash and tool-call parsing |
| `embedding_compliance_spec.rb` | `client.embeddings.embed(...)` array shape |

- Every new transport adapter or provider must pass these by convention.
- These shared examples become the executable form of `API_CONTRACT.md` points that cross-cut endpoint implementation.

---

### Phase 6 — Framework Ecosystem Extraction (weeks 9–12)

**Goal:** formally separate concerns and make the core framework-agnostic by architectural contract (it already is in code).

This phase follows v1.0, uses the existing `ollama/openai_compat` facade as the pattern, and mirrors the blueprint’s dependency graph without rewriting anything.

#### 6.1 `ollama-client-rails` (optional companion gem)

Extracted responsibilities:
- Railtie (`config/initializers/ollama.rb`)
- Generators (`rails g ollama:install`, `rails g ollama:prompt`, etc.)
- `ActiveSupport::Notifications` (`ollama.chat.start` / `finish` / `error`)
- ActiveJob / Sidekiq helpers
- ActionCable streaming bridge

Hard rule: **`ollama-client` imports nothing from Rails**. The existing code already satisfies this.

#### 6.2 `ollama-agent` (already its own gem in this repo)

Confirm the dependency flow:
- `ollama-agent` depends on `ollama-client`, never the other way.
- Memory, planning, MCP, and tool loops live in `ollama-agent`.
- Core SDK never depends on agent concepts.

Existing evidence: `ollama-agent/ollama-agent.gemspec`, `ollama-agent/PRD.md`, and `ollama/agent/*.rb` in the client gem’s `lib/`.

#### 6.3 `ollama-stream` and `ollama-openai` (companion gems)

Existing PRDs and gemspecs already mark these as separable:
- `ollama-openai/` — OpenAI-compatible facade
- `ollama-stream/` — streaming subsystem
- `ollama-observability/` — observability subsystem

Keep them loadable via explicit `require` strings, loadable only at need. This matches the existing:

```ruby
require "ollama/openai"
```

in `ollama-client/lib/ollama/openai_compat.rb`.

---

## Stable Contracts We Will Never Touch

Per `CLAUDE.md`’s rules and the contract in `API_CONTRACT.md`:

1. All method signatures listed in `API_CONTRACT.md` remain stable until v2.0.
2. Error class hierarchy stays intact.
3. Default config values (`base_url`, `timeout`, `retries`, `strict_json`) stay unchanged.
4. Recovery behaviors (auto-pull, backoff, repair prompt retry) are guaranteed.
5. JSON schema validation via `json-schema` stays.
6. Observer hooks interface stays.

These items are non-goal borders for every phase above.

---

## Out of Scope

Per `ARCHITECTURE.md`:

- Vector DB abstractions
- RAG pipelines
- Workflow engines
- Memory systems (RAG/memory belong in `ollama-agent` or `ollama-rails`)

Per ecosystem docs:

- OpenAI/Anthropic/vLLM provider adapters in core — handled by separate adapters/gems.
- ActiveJob/Sidekiq logic inside core.
- Any Rails import into `ollama-client`.

---

## Sequence Summary

```text
Phase 0   Positioning / README / gemspec
    |
Phase 1   Ollama::Messages + Attachment + Prompt DSL (additive)
    |
Phase 2   Ollama::Tool DSL + Ollama::Schema DSL (additive)
    |
Phase 3   Enumerable chat/stream response (additive, hooks unchanged)
    |
Phase 4   Ollama::Middleware namespace + built-in middleware stack
    |
Phase 5   Ollama::Testing + spec/compliance
    |
Phase 6   Formal ecosystem split (ollama-client-rails, confirm ollama-agent)
    |
   v1.0 ship with full positioning and stable public API contract
```

Every phase is additive. User code that currently calls:

```ruby
client.chat(messages: [...], tools: [...])
client.generate(prompt: "...", schema: {...})
```

continues to work byte-for-byte.

---

## Related Files

- `API_CONTRACT.md`
- `CLAUDE.md`
- `ARCHITECTURE.md`
- `ollama-client.gemspec`
- `../ollama-ecosystem.md`
- `../improve-ollama-systems.md`
- `../improve-ollama-systems-structured.md`

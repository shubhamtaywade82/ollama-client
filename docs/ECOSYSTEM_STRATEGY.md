# Ollama Ruby Ecosystem Strategy & Architectural Blueprint

This document defines the overarching architectural strategy, dependency contracts, and governance model for the Ollama Ruby ecosystem. It establishes the foundational guardrails ensuring that as the ecosystem expands across multiple specialized gems, it maintains strict determinism, modularity, and architectural integrity.

---

## 1. Executive Summary & Core Philosophy

The Ollama Ruby ecosystem is designed around a **deterministic kernel** (`ollama-client`) surrounded by **modular companion gems**. 

### The Core Philosophy
1. **Deterministic Kernel**: `ollama-client` is the canonical source of truth for all low-level transport, retry semantics, connection pooling, raw endpoint definitions, and error taxonomy.
2. **Composition over Inheritance**: Companion gems (`ollama-openai`, `ollama-observability`, `ollama-stream`, `ollama-agent`, `ollama-rails`) build upon the core client through well-defined public interfaces and callback hooks rather than monkey-patching or redefining internal transport logic.
3. **Domain Isolation**: Each companion gem encapsulates a single, cohesive domain (e.g., OpenAI compatibility, OpenTelemetry instrumentation, advanced streaming, agent orchestration, Rails integration).

---

## 2. The Dependency Hierarchy & Directionality

To prevent architectural inversion and circular dependencies, all gems in the ecosystem must adhere strictly to the following unidirectional dependency graph:

```
┌────────────────────────────────────────────────────────┐
│               ollama-client (Core Kernel)              │
│    (Transport, Retries, Error Taxonomy, Raw Schemas)   │
└───────────────────────────▲────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
┌────────┴────────┐┌────────┴────────┐┌────────┴────────┐
│  ollama-openai  ││ollama-observab. ││  ollama-stream  │
│(OpenAI Facade)  ││ (OTel Telemetry)││ (SSE & WebSockets│
└────────▲────────┘└─────────────────┘└────────▲────────┘
         │                                     │
         └──────────────────┬──────────────────┘
                            │
                 ┌──────────┴──────────┐
                 │    ollama-agent     │
                 │(Tools, Memory, Plan)│
                 └──────────▲──────────┘
                            │
                 ┌──────────┴──────────┐
                 │    ollama-rails     │
                 │(ActiveJob, Turbo,   │
                 │ ActionCable)        │
                 └─────────────────────┘
```

### Critical Dependency Rules
- **Rule 1**: `ollama-client` must NEVER depend on any companion gem or higher-level concept (e.g., agents, Rails, OpenTelemetry).
- **Rule 2**: Companion gems must declare `ollama-client` as their primary dependency and utilize its public API or hook system.
- **Rule 3**: Higher-level orchestration gems (`ollama-agent`, `ollama-rails`) may compose multiple lower-level companion gems (e.g., `ollama-agent` utilizing `ollama-stream` for tool streaming or `ollama-openai` for LLM interop).

---

## 3. Companion Gem Specifications & Responsibilities

### 1. `ollama-client` (The Kernel)
- **Role**: Canonical infrastructure layer.
- **Responsibilities**: Faraday HTTP/Faraday WebSocket transport, connection pooling, exponential backoff retries, raw API endpoint mapping (`/api/chat`, `/api/generate`, `/api/embeddings`, `/api/pull`), configuration management (`Ollama::Config`), and canonical error taxonomy (`Ollama::Error`, `Ollama::ConnectionError`, `Ollama::TimeoutError`, `Ollama::RateLimitError`).
- **Prohibited**: High-level workflow orchestration, third-party framework coupling.

### 2. `ollama-openai` (Protocol Interop)
- **Role**: Drop-in OpenAI compatibility layer.
- **Responsibilities**: Translating OpenAI-style requests (`client.chat(parameters: {})`) into native Ollama payloads, mapping OpenAI function definitions to Ollama tool schemas, normalizing Ollama responses into OpenAI JSON structures (`chatcmpl-*`), and companion support for frameworks like LangChain, Vercel AI SDK, and ruby-openai consumers.
- **Prohibited**: Custom HTTP transport implementations.

### 3. `ollama-observability` (Telemetry & Logging)
- **Role**: Enterprise-grade observability layer.
- **Responsibilities**: Subscribing to `ollama-client` hooks (`on_response`, `on_token`, `on_error`) to generate OpenTelemetry tracing spans, tracking metrics (Time-to-First-Token, latency histograms, prompt/completion token counters), and emitting structured JSON logs. Supports payload redaction for PII/PHI compliance.
- **Prohibited**: Modifying raw API responses or interfering with inference execution.

### 4. `ollama-stream` (Advanced Streaming & Transport)
- **Role**: High-performance streaming runtime.
- **Responsibilities**: Encapsulating SSE streams into formal `Ollama::Stream::StreamObject` instances supporting pause, resume, and cancellation; managing persistent bidirectional WebSocket sessions; providing backpressure and queue bounding (`FlowController`); implementing incremental JSON fragment recovery (`IncrementalParser`); and offering a Rack-compatible SSE proxy adapter.
- **Prohibited**: Re-implementing base Faraday connection logic.

### 5. `ollama-agent` (Orchestration & Tooling)
- **Role**: Autonomous agent execution framework.
- **Responsibilities**: Defining standardized tool contracts (`Ollama::Agent::Tool`), managing tool registries, maintaining conversation memory (`WindowMemory`, `SummaryMemory`), executing autonomous ReAct/Plan-and-Solve agent loops (`Executor`), and providing structured JSON output parsing.
- **Prohibited**: Direct HTTP transport management.

### 6. `ollama-rails` (Rails Integration)
- **Role**: Idiomatic Ruby on Rails integration.
- **Responsibilities**: Providing Rails Railtie for zero-config initialization, wrapping async inference in ActiveJob (`Ollama::Rails::GenerateJob`, `ChatJob`), broadcasting live stream tokens over ActionCable/Turbo Streams (`Ollama::Rails::BroadcastHelpers`), offering ActiveRecord mixins (`Ollama::Rails::Embeddable` for pgvector/neighbor integration), and providing Rake tasks for model management (`ollama:pull`, `ollama:list`).
- **Prohibited**: Modifying core Ruby runtime behavior outside the Rails application context.

---

## 4. Architectural Guardrails & Extension Mechanisms

### The Hook System
To enable companion gems to extend functionality without monkey-patching, `ollama-client` exposes a robust hook and middleware architecture:

```ruby
# Example of Hook Subscription in Companion Gems
config.on_response = ->(raw_response, metadata) {
  # Used by ollama-observability for metrics and logging
  Telemetry.record_latency(metadata[:duration])
}

client.chat(
  model: "llama3",
  messages: history,
  hooks: {
    on_token: ->(chunk, logprobs) { # Used by ollama-stream },
    on_tool_call: ->(tool_call) { # Used by ollama-agent },
    on_error: ->(error) { # Used by ollama-observability }
  }
)
```

### Error Handling & Taxonomy
All companion gems must catch base `Ollama::Error` exceptions from `ollama-client` and either allow them to bubble up or wrap them in domain-specific exceptions that inherit from `Ollama::Error` (e.g., `Ollama::Openai::Error < Ollama::Error`).

---

## 5. Development & Workspace Governance

### Local Dependency Mapping
During development, all companion gems must reference the local `ollama-client` kernel in their `Gemfile` to ensure continuous integration and contract verification across the workspace:

```ruby
# Gemfile for Companion Gems
source "https://rubygems.org"
gemspec

# Enforce local workspace dependency
gem "ollama-client", path: "../ollama-client"
```

### Verification & Testing
Every companion gem must maintain an independent RSpec test suite verifying its specific domain logic against mock `Ollama::Client` instances. Contract tests must ensure that changes in `ollama-client` do not break companion gem facades.

---

## 6. Roadmap & Future Evolution

1. **Phase 1: Foundation (Completed)**
   - Core transport, retry semantics, error taxonomy, and configuration in `ollama-client`.
   - OpenAI interop facade in `ollama-openai`.
   - Enterprise telemetry in `ollama-observability`.
   - Advanced streaming primitives in `ollama-stream`.

2. **Phase 2: Orchestration & Frameworks (Current)**
   - Autonomous agent loops and tool calling in `ollama-agent`.
   - Idiomatic Rails integrations in `ollama-rails`.

3. **Phase 3: Advanced Optimization & Ecosystem Scaling (Future)**
   - Native C/Rust extensions for high-throughput incremental JSON parsing.
   - Distributed multi-node Ollama cluster balancing and routing gems.

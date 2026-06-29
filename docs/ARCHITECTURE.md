# ollama-client Architecture

This document specifies the frozen v1 architecture design of `ollama-client`.

```text
ollama-client
│
├── Config
├── Request
├── Response
├── Errors
│
├── Transport
│   ├── HTTP
│   ├── Mock
│   └── Streaming
│
├── Middleware
│   ├── Logger
│   ├── Metrics
│   ├── Cache
│   ├── Tracing
│   └── Base
│
├── Policies
│   ├── Retry
│   ├── AutoPull
│   ├── RepairJson
│   ├── SchemaRepair
│   ├── CapabilityValidation
│   └── RateLimit
│
├── Core
│   ├── Chat
│   ├── Generate
│   ├── Embeddings
│   ├── Models
│   └── Version
│
├── Ruby
│   ├── Messages
│   ├── Tool
│   ├── Schema
│   ├── TypedResponses
│   ├── Streaming
│   └── Testing
│
├── Plugins
│
├── Rails (optional)
│
└── Compliance Tests
```

---

## 1. Request/Response Pipeline Design

All lifecycle hooks, logging, retries, and errors run inside a single composable pipeline of middleware:

```text
Request
   │
   ▼
Middleware (Logger / Caching)
   │
   ▼
Policies (Retry / AutoPull / JsonRepair)
   │
   ▼
Transport Terminal (HTTP / Mock)
   │
   ▼
Response
   │
   ▼
Typed Objects
```

### Composable Middleware Stack

Every middleware implements the following Rack/Faraday-style interface:

```ruby
class Base
  def initialize(app, **options)
    @app = app
    @options = options
  end

  def call(request)
    @app.call(request)
  end
end
```

---

## 2. Core Abstractions

### Request Object

An immutable container for all request parameters, keeping core logic completely decoupled from HTTP adapters or JSON payloads.

```ruby
class Request
  attr_reader :endpoint, :model, :messages, :prompt, :images, :tools, :schema, :options, :stream

  def initialize(endpoint:, **args)
    @endpoint = endpoint
    @model = args[:model]
    @messages = args[:messages]
    @prompt = args[:prompt]
    @images = args[:images]
    @tools = args[:tools]
    @schema = args[:schema]
    @options = args[:options] || {}
    @stream = args[:stream]
    freeze
  end

  def streaming?
    hooks = @options[:hooks]
    (hooks && !hooks.empty?) || @stream == true
  end
end
```

### Response Object

Typed accessors wrapping LLM returns instead of raw HTTP hashes:

```ruby
response.message.content
response.done?
response.total_duration
```

### Policies Namespace

All recovery policies (AutoPull, Retry, RepairJson) live in the `Ollama::Policies` plural namespace for consistency.

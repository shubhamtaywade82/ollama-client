# RubyLLM → ollama-client Adoption Matrix

**Purpose:** decide, feature by feature, what `ollama-client` should take from RubyLLM, what it should
take *and improve*, what it should refuse, and what belongs in an ecosystem gem — so the next build
phase is driven by a decision, not by opportunity.

**Positioning premise:** RubyLLM is breadth (one interface across ~12 providers). `ollama-client` is
depth (the complete Ruby runtime for one provider). Adoption is therefore about **ergonomics parity**,
not **scope parity**. Anything RubyLLM does *because* it must abstract many providers is a candidate
for rejection.

**Sources**

- RubyLLM public API: [rubyllm.com](https://rubyllm.com/) — [chat](https://rubyllm.com/chat/),
  [tools](https://rubyllm.com/tools/), [models](https://rubyllm.com/models/),
  [streaming](https://rubyllm.com/streaming/), [rails](https://rubyllm.com/rails/),
  [configuration](https://rubyllm.com/configuration/) (surface as of RubyLLM ~1.15, incl. `RubyLLM::Agent`).
- `ollama-client` current state: this repository at `v1.3.0` (`lib/ollama/version.rb`), ~5.8k LOC in `lib/`,
  public surface frozen by [`API_CONTRACT.md`](../API_CONTRACT.md).

---

## Verdict legend

| Verdict | Meaning |
|---|---|
| **COPY** | Adopt the concept close to as-is. RubyLLM's shape is right and provider-neutral. |
| **IMPROVE** | Adopt the concept, but ship a strictly better version using Ollama-specific depth. |
| **REJECT** | Do not build. Either it is a multi-provider artifact, or Ollama has no such capability. |
| **ECOSYSTEM** | Right idea, wrong gem. Belongs in `ollama-rails` / `ollama-agent` / `ollama-testing` / `ollama-observability`. |
| **HAVE** | Already exists here, at parity or better. No work beyond docs. |

---

## A. Chat & conversation

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| A1 | Stateful conversation object | `chat = RubyLLM.chat(model:)`; `chat.ask("…")` twice keeps history | **None.** `chat` is a stateless one-shot on `Client` (`lib/ollama/client/chat.rb:29`) returning `Ollama::Response`. Callers hand-manage `messages:` arrays | **COPY** | `Ollama::Chat` — `client.chat(model:)` with no `messages:` returns a `Chat`; `chat.ask` appends and returns `Ollama::Response`. Highest-leverage single item in this document |
| A2 | Backwards-compatible entry point | n/a (RubyLLM never had a hash API) | `chat(messages:, …)` is contract-frozen until v2.0 | **IMPROVE** | Overload, don't replace: `messages:` present → today's exact behavior; `messages:` absent → `Ollama::Chat`. Zero contract breakage |
| A3 | System prompt helper | `with_instructions(text, append: false)` | Only `Ollama::Messages#system` (`lib/ollama/messages.rb:29`) | **COPY** | `chat.with_instructions` delegating to `Messages#system` (which already does replace-or-append) |
| A4 | Fluent config builders | `with_model`, `with_temperature`, `with_params`, `with_headers` | Per-call kwargs + `Ollama::Options` + per-client `Config` | **IMPROVE** | Add the fluent set *plus* Ollama-native builders RubyLLM cannot have: `with_think(:high)`, `with_keep_alive("30m")`, `with_num_ctx(32_768)`, `with_options(Ollama::Options)` |
| A5 | Conversation history access | `messages`, `add_message`, `reset_messages!` | `Ollama::Messages` builder exists but is not attached to a conversation | **COPY** | `chat.messages` returns the `Messages` builder; `add_message`, `reset!` |
| A6 | History hygiene across turns | Not addressed — RubyLLM replays raw history | `HistorySanitizer` + `ModelProfile#history_policy` (`:exclude_thoughts`) already exist (`lib/ollama/history_sanitizer.rb`, `lib/ollama/model_profile.rb:123`) | **HAVE / exceed** | Wire the existing sanitizer into `Ollama::Chat` by default. This is depth RubyLLM structurally cannot match — it does not know that Gemma-4 thinking blocks must be dropped from replayed history |
| A7 | Message/response object | `response.content`, `.model_id`, `.raw`, `.tokens.{input,output,cache_read,thinking}`, `.cost.total` | `Ollama::Response` with `content`, `usage`, `latency_ms`, `total_duration`, `eval_count`, `logprobs` (`lib/ollama/response.rb`) | **IMPROVE** | Keep `usage`. **Reject `cost`** (local inference has no per-token price) and spend that slot on `tokens_per_second`, `load_duration_ms`, `prompt_eval_rate` — the numbers that actually matter locally |
| A8 | Lifecycle callbacks | `before_message`, `after_message`, `before_tool_call`, `after_tool_result` (legacy `on_*` deprecated) | `hooks: {on_token:, on_thought:, on_tool_call:, on_error:, on_complete:}` (contract-frozen) + separate `StreamEvent` struct + separate `StreamingObserver` | **IMPROVE** | Do **not** add a third callback system. Collapse to one typed `Ollama::StreamEvent` bus (`lib/ollama/stream_event.rb` already defines the taxonomy), with `hooks:` retained as the frozen adapter over it |
| A9 | Prompt caching | `cache_prompts`, cache token accounting | n/a — Ollama has no prompt-cache billing surface | **REJECT** | Ollama's equivalent lever is `keep_alive` + preload, already covered by A4/E5 |
| A10 | Reusable assistant preset | `class X < RubyLLM::Agent; model …; instructions …; tools … end` | `Ollama::Agent::Executor`, `Ollama::Agent::Planner` in core (`lib/ollama/agent/`) | **ECOSYSTEM** | Agent presets → `ollama-agent`. Core ships `Ollama::Chat` only. See §L for the executor question |

---

## B. Tools

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| B1 | Class-based tool definition | `class X < RubyLLM::Tool; description …; param …; def execute(**) end` | `Ollama::ToolDSL` with `description`, `tool_name`, `input do … end`, `output do … end`, `call { }` (`lib/ollama/tool_dsl.rb`) | **IMPROVE** | Keep the schema DSL (it is better — typed `input`/`output` blocks). Replace the confusing `call { }` "constructor" block with a plain `#execute(**kwargs)` instance method. `to_tool_hash` stays |
| B2 | Nested/complex params | `params do object :w do … end; array :p, of: :string end` | `SchemaDSL` has `object`/`array` but `object` takes a raw `properties:` hash — no nested block (`lib/ollama/schema_dsl.rb:61`) | **COPY** | Add block form to `SchemaDSL#object` and `of:` to `#array`. Small change, removes the last reason to hand-write JSON Schema |
| B3 | Signature inference | v1.15+: builds schema from `execute` kwargs when no `param` given | Exists but buried in `Agent::Executor#infer_parameters` and types everything as `"string"` | **IMPROVE** | Promote inference to `ToolDSL`, and infer types from Ruby defaults/`Data` members rather than defaulting to string |
| B4 | Attaching tools | `with_tool(T)`, `with_tools(A, B)` | `chat(tools: [T.to_tool_hash])` — user must serialize manually | **COPY** | `chat.with_tool(T)` accepting a `ToolDSL` subclass, `Ollama::Tool` DTO, or raw hash |
| B5 | Tool call parsing | Provider-normalized | `Response::Message::ToolCall` + `Function#arguments` with JSON-string fallback (`lib/ollama/response.rb:165`) — plus `ToolIntent` fallback for models that emit tool calls as prose | **HAVE / exceed** | Nothing. `lib/ollama/client/tool_intent.rb` has no RubyLLM equivalent |
| B6 | Halt the loop | `halt "…"` skips the model's post-tool commentary | None | **COPY** | Cheap, high value once a loop exists (§L) |
| B7 | Tool choice / call count | `choice: :auto\|:required\|:none\|Tool`, `calls: :many\|:one` | None | **PARTIAL / verify** | `/api/chat` does not expose `tool_choice`; the OpenAI-compat endpoint does. Ship `choice:` only where the provider supports it (`lib/ollama/providers/openai.rb`), and emulate `:none` by omitting `tools:`. Do not fake `:required` |
| B8 | Concurrent tool execution | `concurrency: :threads \| :fibers` | None | **ECOSYSTEM** | Scheduling policy → `ollama-agent` |
| B9 | Automatic execution loop | Core runs the tool loop inside `ask` | `Agent::Executor` (in core, undocumented in `API_CONTRACT.md`) | **CONTESTED** | See §L — this is the one boundary decision that must be made before A1 ships |
| B10 | Argument safety | Docs-only guidance ("treat as untrusted") | `Executor` does keyword/positional coercion + alias guessing (`directory`→`path`) | **IMPROVE** | Validate tool arguments against the declared `input` schema *before* dispatch using the existing `SchemaValidator`, and drop the alias guessing — it is a silent-wrong-behavior generator |

---

## C. Structured output

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| C1 | Schema class DSL | `class S < RubyLLM::Schema; string :name; number :price; array :f do string end; end` | `Ollama::SchemaDSL.define { … }.to_h` — block/instance form, not a subclassable class | **COPY** | `class TradeSignal < Ollama::Schema` with the same field methods. Keep `SchemaDSL.define` as the anonymous form |
| C2 | Attaching a schema | `chat.with_schema(S)` → `response.content` is a parsed Hash | `generate(schema:)` → Hash; `chat(format:)` → raw String the caller must `JSON.parse` | **IMPROVE** | `chat.with_schema(S)`. Non-negotiable per `CLAUDE.md`: `generate` keeps its String-vs-Hash rule unchanged; the new typed path lives on `Chat` |
| C3 | Validation & repair | Provider-side JSON mode; no repair loop | `strict_json` + `SchemaValidator` + repair-prompt retry — **but only on `generate`**. `chat(format:)` bypasses validation and repair entirely | **IMPROVE** | **Real defect, not just a gap.** Route `chat(format:)`/`with_schema` through the same validate→repair→retry pipeline. Closing this is worth more than any DX item in this table |
| C4 | Typed result objects | Returns a Hash | Returns a Hash | **IMPROVE / differentiate** | `signal.direction` not `hash["direction"]`. Schema class instantiates a typed object with coercion. This is the flagship differentiator called out in the strategy |
| C5 | Incremental / streaming parse | None | `JsonFragmentExtractor` extracts balanced JSON from partial text (`lib/ollama/json_fragment_extractor.rb`) | **HAVE → extend** | Feed the extractor from the stream so partial structured output can render live. RubyLLM has no answer here |
| C6 | Enum / constraint coverage | `string :x, enum: […]` | `enum`, `minimum`, `maximum`, `description`, `default`, `optional` | **HAVE** | Add `pattern`, `format`, `minItems` for completeness |

---

## D. Streaming

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| D1 | Block streaming | `chat.ask("…") { \|chunk\| print chunk.content }` | `hooks: {on_token:}` — works, but the block form is what people expect | **COPY** | `chat.ask(…) { \|chunk\| }`; presence of a block implies `stream: true`, exactly as `hooks:` does today (`lib/ollama/client/chat.rb:74`) |
| D2 | Chunk object | `RubyLLM::Chunk` with `content`, `role`, `model_id`, `tool_calls`, `tokens`, `thinking` | `StreamEvent(type:, data:, model:)` with `thought?`/`answer?`/`tool_call?`/`terminal?` predicates and `to_jsonl` | **HAVE / exceed** | Typed event *taxonomy* beats an untyped chunk — reasoning is separated from answer at the type level. Just expose it publicly |
| D3 | Final message after streaming | `ask` returns the complete message even when streaming | `chat` returns assembled `Ollama::Response` via `ChatStreamProcessor` | **HAVE** | — |
| D4 | Stream cancellation | **None documented** | None | **IMPROVE / exceed** | `stream = chat.stream("…")`; `stream.cancel`, `stream.closed?`, `stream.metrics`, `stream.each_chunk`. This is a clear "exceed RubyLLM" slot and is already scoped in `docs/rfcs/0001-stream-runtime.md` |
| D5 | Streaming errors | Raises `RubyLLM::Error` subclasses mid-stream | `Ollama::StreamError` from `{"error":…}` NDJSON lines, `on_error` hook | **HAVE** | — |
| D6 | Turbo/ActionCable bridge | Documented Rails pattern | None | **ECOSYSTEM** | `ollama-rails` |
| D7 | Async / fibers | Works under `Async`; concurrency options in tools | None; `docs/rfcs/0004-async-runtime.md` drafted | **ECOSYSTEM (later core)** | Keep `Net::HTTP` core; async runtime as `ollama-stream` or an opt-in transport adapter — the `Transport::Base` boundary already supports this |

---

## E. Models & runtime — *the differentiation zone*

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| E1 | Model registry object | `RubyLLM.models` → collection | `list_models` → `Array<Hash>` (`lib/ollama/client/model_management.rb:233`) | **IMPROVE** | `client.models` → `Ollama::ModelCollection`; `client.model("qwen3:8b")` → `Ollama::Model` |
| E2 | Registry filters | `all`, `chat_models`, `embedding_models`, `by_provider`, `by_family`, `find` | None (raw array) | **COPY** | `.running`, `.embedding`, `.vision`, `.tools`, `.thinking`, `.by_family`, `.find` — filters keyed off `Capabilities` + `ModelProfile`, not a static catalog |
| E3 | Model metadata source | **Static catalog** refreshed from models.dev + `refresh!` + `save_to_json` | Live `/api/tags` + `/api/show`, with `Capabilities.for` inference (`lib/ollama/capabilities.rb`) | **IMPROVE / exceed** | Live-first is the whole thesis. `model.capabilities` should prefer the server's own `/api/show` capability list and fall back to name/family heuristics — today `Capabilities.for` is heuristics-only |
| E4 | Model attributes | `context_window`, `max_tokens`, `supports_vision?`, `supports_functions?`, `family`, pricing | `ModelProfile` (static family table, `lib/ollama/model_profile.rb:14`) + capability hash | **IMPROVE** | `Ollama::Model#name/family/parameters/quantization/context_window/capabilities` — sourced from `/api/show` `model_info`, which carries real per-model context length and quantization. Static tables become fallback only |
| E5 | Runtime state | **Impossible for RubyLLM** | `list_running`/`ps`, `load_model`, `unload_model` exist but return hashes | **IMPROVE / exceed** | `model.running?`, `.loaded_at`, `.expires_at`, `.vram`, `.memory`, `.load`, `.unload`, `.performance.tokens_per_second`. This is the `/models` command in the AI Runtime Shell, and no multi-provider SDK can offer it |
| E6 | Lifecycle operations | `refresh!` only | `pull`, `push_model`, `delete_model`, `copy_model`, `create_model`, `blob_exists?`, `create_blob` | **HAVE / exceed** | Re-expose as instance methods on `Ollama::Model` (`model.pull`, `model.copy("prod")`) — same HTTP calls, better surface |
| E7 | Pricing / cost tracking | `input_price_per_million`, `cost.total` | None | **REJECT** | Meaningless locally. Replace with the E5 performance surface |
| E8 | Alias resolution | `aliases.json` maps `claude-sonnet` → versioned id | None — `qwen3` vs `qwen3:8b` is the caller's problem | **COPY (small)** | Resolve bare names against installed tags; raise a typed error listing near-matches instead of a bare 404 |
| E9 | Unknown-model escape | `assume_model_exists: true` | 404 → auto-pull → retry (contract-guaranteed) | **HAVE / exceed** | — |

---

## F. Other modalities

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| F1 | Embeddings | `RubyLLM.embed(text)` → `Embedding` with `vectors`, `model`, `input_tokens` | `client.embeddings.embed(model:, input:)` → raw `Array<Float>`; `model:` is required | **COPY** | `client.embed("text")` using a new `config.default_embedding_model`; return an `Ollama::Embedding` object (`vectors`, `model`, `dimensions`, `usage`) that still `to_ary`s to the raw vector for compatibility |
| F2 | Attachments | `chat.ask("what is this?", with: "image.png")` — auto-detects type | `Ollama::Attachment.file/base64/url` + `MultimodalInput` + `inputs:` kwarg | **COPY (ergonomics only)** | Add `with:` sugar over the existing typed machinery. Keep `inputs:` as the explicit form |
| F3 | Image generation | `RubyLLM.paint` | None | **REJECT** | Ollama does not generate images |
| F4 | Transcription | `RubyLLM.transcribe` | None | **REJECT** | Not an Ollama endpoint |
| F5 | Moderation | `RubyLLM.moderate` | None | **REJECT** | Not an Ollama endpoint. A safety-model convention could live in `ollama-agent` |
| F6 | Thinking / reasoning | Surfaced as a `thinking` chunk field only | `think: true\|"high"\|"medium"\|"low"`, per-family `think_trigger` (`:flag` vs `:system_prompt_tag`), separated reasoning stream, `UnsupportedThinkingModel` | **HAVE / exceed** | Document it as a headline feature. `PromptAdapters` handling Gemma-4's tag-based thinking is genuinely unmatched |

---

## G. Configuration, transport, errors

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| G1 | Global config | `RubyLLM.configure { \|c\| … }` | `OllamaClient.config` + per-client `Config` (per-client is the documented default) | **HAVE** | Keep per-client primacy — `CLAUDE.md` forbids mutating global config with live clients. Thread-safety here is already better |
| G2 | Isolated contexts | `RubyLLM.context { \|c\| … }` → independent, thread-safe | `Config.new` + `Client.new(config:)` — the same thing, less ceremony | **HAVE** | Documentation only |
| G3 | Retry tuning | `max_retries`, `retry_interval`, `retry_backoff_factor`, `retry_interval_randomness` | `config.retries` only; backoff hardcoded `2 ** attempt`, no jitter | **COPY** | Add interval/factor/jitter knobs. Contract-safe: `API_CONTRACT.md` explicitly permits retry-timing changes and new config attributes with compatible defaults |
| G4 | Logging | `logger`, `log_file`, `log_level`, `log_stream_debug` | `config.on_response` callback only | **COPY (core) + ECOSYSTEM** | Minimal `config.logger` in core; OTel/metrics/exporters → `ollama-observability` |
| G5 | Proxy / connection | `http_proxy`, Faraday connection options | `http_connection_options` (ssl + timeouts) | **COPY** | Proxy support + connection pooling (already on `ROADMAP.md`) |
| G6 | Transport swap | Faraday middleware, not a documented public seam | `Transport::Base`/`NetHTTP`/`Mock` factory (`lib/ollama/transport.rb`) | **HAVE / exceed** | Formalize as the middleware stack in `IMPROVE.md` Phase 4 |
| G7 | Raw escape hatch | `with_params`, `response.raw` | `client.raw.get/post/delete` (`lib/ollama/client/raw.rb`) + `client.openai` facade | **HAVE / exceed** | — |
| G8 | Error taxonomy | `Error`, `BadRequest`, `Unauthorized`, `RateLimit`, `ServerError`, `ModelNotFound`, … | 11 typed errors with documented retryability + recovery guarantees | **HAVE / exceed** | — |
| G9 | Multi-key failover | None | `ApiKeyPool` + round-robin + rate-limit rotation (`lib/ollama/api_key_pool.rb`) | **HAVE / exceed** | Relevant to Ollama Cloud; keep and document |

---

## H. Rails & test/observability tooling

| # | RubyLLM capability | RubyLLM API | ollama-client today | Verdict | Target |
|---|---|---|---|---|---|
| H1 | Persistence | `acts_as_chat`, `acts_as_message`, `acts_as_tool_call`, `acts_as_model` | None | **ECOSYSTEM** | `ollama-rails`. Hard rule stands: core imports nothing from Rails |
| H2 | Generators | `ruby_llm:install`, `:chat_ui`, `:load_models` | None | **ECOSYSTEM** | `ollama-rails` |
| H3 | Empty-assistant-message persistence pattern | Core Rails behavior; documented as blocking `validates :content, presence: true` | n/a | **REJECT the pattern** | Do not inherit this design flaw. `ollama-rails` should persist on completion, or persist a distinct `pending` state |
| H4 | Background jobs / Turbo | Documented patterns | None | **ECOSYSTEM** | `ollama-rails` |
| H5 | Deterministic test doubles | VCR in RubyLLM's own suite; no shipped public test API | `Transport::Mock` shipped in-gem; `docs/testing/REPLAY_SYSTEM.md` drafted | **HAVE → ECOSYSTEM** | `Ollama::Testing` helpers (`stub_chat`, `stub_stream`, `stub_error`) per `IMPROVE.md` Phase 5, then extract to `ollama-testing`. A shipped mock transport is a real advantage — RubyLLM users reach for WebMock themselves |
| H6 | Observability | Logging only | `on_response` hook, `Response#usage`, `#latency_ms` | **ECOSYSTEM** | `ollama-observability` (OTel spans, token metrics) |

---

## I. Where ollama-client already exceeds RubyLLM

No adoption work — these are the marketing surface and should be lifted into the README's lead section:

1. **Thinking/reasoning as a first-class, per-family concern** — `think:` levels, `think_trigger` (API flag vs. system-prompt tag), reasoning separated from answer in the stream, `UnsupportedThinkingModel`.
2. **Prompt adapters per model family** — Gemma-4/Qwen/DeepSeek/generic (`lib/ollama/prompt_adapters/`). RubyLLM cannot do this without becoming Ollama-specific.
3. **History sanitization policies** — dropping thoughts from replayed history is a correctness issue in multi-turn agent loops that RubyLLM leaves to the user.
4. **Structured-output repair loop** — validate → repair-prompt → retry, contract-guaranteed. RubyLLM trusts provider JSON mode.
5. **Tool-intent recovery** — parsing tool calls from models that emit them as prose.
6. **Auto-pull on 404** — a guaranteed recovery behavior that only makes sense for a local runtime.
7. **Model lifecycle** — `ps`, `load`/`unload`, `keep_alive`, `create`/`copy`/`push`/blobs.
8. **Shipped mock transport** and an explicit `API_CONTRACT.md`.
9. **Multi-key failover** for Ollama Cloud.
10. **Typed stream event taxonomy** with JSONL tracing built in.

## J. Where RubyLLM is straightforwardly ahead

Stated plainly, because the matrix above is otherwise easy to read as self-congratulation:

1. **No conversation object.** `chat.ask` twice is the single most expected thing in a modern LLM SDK, and it does not exist here (A1).
2. **Tools do not execute.** `ToolDSL` produces a schema; nothing wires it to a callable in the public API (B1/B4/B9).
3. **Structured output on `chat` is unvalidated** and returns a raw string (C2/C3).
4. **No streaming block form** — hooks are more powerful and less familiar (D1).
5. **Models are hashes**, not objects (E1).
6. **Embeddings require an explicit `model:`** every call and return bare arrays (F1).
7. **No Rails story at all** (H1–H4).

Items 1–6 are all fixable additively, without touching a frozen signature.

## K. Ollama API coverage gaps (independent of RubyLLM)

Depth positioning means "100% Ollama API coverage" must be literally true. Open items to verify against
the current Ollama API docs before claiming it:

- `web_search` / `web_fetch` cloud endpoints (introduced 2025, `ollama.com` API-key gated) — **verify and cover**; `client.raw` works today but this deserves a first-class surface given the Cloud story.
- `/api/embeddings` (legacy singular) alongside `/api/embed` — currently only the plural path is used.
- `/api/generate` `context` parameter (deprecated but present), `suffix` (FIM) — `suffix`/`raw` are supported; confirm `context` handling.
- Streamed `create`/`pull`/`push` progress: `hooks[:on_progress]` exists but is not in `API_CONTRACT.md`.
- `/api/show` `model_info` fields (real context length, quantization, parameter count) are fetched but discarded — they are the raw material for E4.

## L. The one contested boundary: who runs the tool loop?

The strategy says `ollama-client` owns tool *schema, parsing, validation, normalization*, and
`ollama-agent` owns *execution loops, permissions, scheduling, policies*. RubyLLM puts the loop in core.
Meanwhile `Ollama::Agent::Executor` already sits in this gem's `lib/`, undeclared in `API_CONTRACT.md`.

**Recommendation: put a bounded loop in core, and keep policy out.**

Core (`ollama-client`) ships:

- `chat.with_tool(T)` and `chat.ask(…)` resolving tool calls automatically up to `max_tool_rounds:` (default small, e.g. 5), raising a typed `Ollama::ToolLoopExhausted` past that.
- Synchronous, in-order execution. Argument validation against the declared schema. `halt` support.

`ollama-agent` owns: permissions and sandboxing, concurrency/scheduling, retries and replanning,
memory, multi-agent orchestration, human-in-the-loop approval, budget enforcement.

Rationale: without execution, `with_tool` is a lie — the user still writes the loop, and the "most Ruby
developers don't need `ollama-agent`" goal fails on the most common use case. A bounded, policy-free
loop is a *protocol completion*, not an agent framework. `Agent::Executor` then either becomes the
private implementation of that loop or moves out to `ollama-agent` at the same time — it should not
remain a public-ish class in core with no contract.

---

## M. Prioritized build order

Derived strictly from the matrix. Every P0/P1 item is additive; none touches a signature frozen by
`API_CONTRACT.md`.

### P0 — Correctness (ship before any ergonomics)

| Item | Ref | Why first |
|---|---|---|
| Route `chat(format:)` through validate → repair → retry | C3 | Two structured-output paths with different reliability guarantees is a defect, and the gem's core claim is deterministic structured output |
| Prefer `/api/show` server capabilities over name heuristics | E3 | `Capabilities.for` currently guesses from model names; the server knows |
| Decide the tool-loop boundary and document it | L | Blocks P1 tool work and `Agent::Executor`'s fate |

### P1 — Ergonomics parity (the RubyLLM lesson)

| Item | Ref |
|---|---|
| `Ollama::Chat` stateful conversation + `ask` (+ history sanitizer wired in) | A1, A2, A5, A6 |
| `with_instructions` / `with_model` / `with_temperature` / `with_think` / `with_keep_alive` | A3, A4 |
| Block streaming `chat.ask(…) { \|chunk\| }` over the existing NDJSON path | D1 |
| `class T < Ollama::Tool` with `#execute`; `chat.with_tool(T)`; bounded loop; `halt` | B1, B4, B6, B9 |
| `class S < Ollama::Schema`; `chat.with_schema(S)` → typed object | C1, C2, C4 |
| `client.embed("text")` + `default_embedding_model` + `Ollama::Embedding` | F1 |
| `ask(…, with: "image.png")` sugar | F2 |

### P2 — Depth that exceeds RubyLLM

| Item | Ref |
|---|---|
| `Ollama::Model` + `Ollama::ModelCollection` with live filters and lifecycle methods | E1, E2, E4, E6 |
| Runtime introspection: `running?`, `expires_at`, `vram`, `performance.tokens_per_second` | E5 |
| `Ollama::Stream` with `cancel`, `closed?`, `metrics`, `each_chunk` | D4 |
| Incremental structured-output parsing off the stream | C5 |
| Nested schema blocks, tool signature inference, schema-validated tool arguments | B2, B3, B10 |
| Retry/jitter knobs, `config.logger`, proxy support, model alias resolution | G3, G4, G5, E8 |

### P3 — Ecosystem extraction

`ollama-testing` (H5) → `ollama-rails` (H1–H4) → `ollama-observability` (H6) → `ollama-agent` boundary
finalized (A10, B8, L) → `ollama-stream` / async (D7).

## N. API contract impact

| Change class | Contract effect |
|---|---|
| `Ollama::Chat`, `Ollama::Model`, `Ollama::Schema`, `Ollama::Embedding`, `Ollama::Stream` | New classes — additive, no impact |
| `client.chat` with no `messages:` returning a `Chat` | New arity path; `messages:`-present behavior byte-identical. Permitted ("new optional keyword arguments") — but call it out explicitly in the contract |
| `chat(format:)` gaining validation/repair | **Behavior change.** Today it returns unvalidated content; after, it can raise `SchemaViolationError`. Requires a minor-version note, and arguably a `strict:` opt-out on `chat` to mirror `generate` |
| `Ollama::Response#cost` | Never — explicitly rejected (E7) |
| `config.retry_interval`, `config.logger`, `config.default_embedding_model`, `config.http_proxy` | Additive with compatible defaults — permitted |
| `Ollama::ToolLoopExhausted` | New error under the existing hierarchy — permitted |
| `Agent::Executor` | Must be either declared public with a contract, made private, or moved to `ollama-agent`. Currently undefined status |

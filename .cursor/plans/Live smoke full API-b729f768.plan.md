<!-- b729f768-851f-40b0-ac2a-1f657ae079e1 -->
---
todos:
  - id: "gap-matrix"
    content: "Add run_safe checks for list_model_names, tags, ps/list_running, show_model, Response accessors, Options on chat/generate, chat format/tools/logprobs/stream flags/keep_alive/profile false, generate system/return_meta/keep_alive/on_complete, embeddings batch + optional kwargs"
    status: pending
  - id: "capability-gates"
    content: "Centralize Capabilities-based SKIP for tools, thinking, vision, logprobs; add env overrides (tools/vision/thinking models) aligned with API_CONTRACT"
    status: pending
  - id: "optional-destructive"
    content: "Env-gated copy_model + delete_model cleanup; document all new env vars in script header"
    status: pending
  - id: "library-smoke"
    content: "InvalidJSONError path for JsonFragmentExtractor; SchemaValidator.validate! trivial case; optional OllamaClient.config read-only"
    status: pending
  - id: "verify"
    content: "Run rubocop + live script locally; tune prompts for flaky models"
    status: pending
isProject: false
---
# Expand live smoke to cover public API surface

## Current baseline

[`script/live_branch_smoke.rb`](script/live_branch_smoke.rb) already hits: `list_models`, `version`, `ModelProfile.for`, `client.profile`, capabilities on a list entry, `JsonFragmentExtractor`, `generate` (plain, schema, stream hooks), `chat` (plain, `profile: :auto`, stream hooks with `on_token`/`on_thought`), `MultimodalInput` (text-only), `history_sanitizer`, `StreamEvent`, single-input `embeddings`, optional Gemma via `OLLAMA_GEMMA_MODEL`.

## Reality check on “100%”

- **Feasible:** Exercise every **documented public method / keyword** in [`API_CONTRACT.md`](API_CONTRACT.md) with a live call, using **SKIP** when the local Ollama build or pulled models lack support (same pattern as `gemma_profile` and embeddings today).
- **Not feasible in one script:** Every internal branch (retries, repair prompts, auto-pull success paths, every error subclass) without brittle fault injection; that remains **unit/integration RSpec** territory ([`spec/integration/client_integration_spec.rb`](spec/integration/client_integration_spec.rb)).

The plan targets **contract-complete live coverage** plus clear **SKIP reasons**, not line-level coverage.

## Gaps to close (mapped to API_CONTRACT)

| Area | Today | Add |
|------|-------|-----|
| Model management | `list_models`, `version` | `list_model_names`, `list_running` / `ps`, `show_model(model: @model)` (non-verbose); call `client.tags` once to assert alias path; optional **`copy_model` + `delete_model`** only when env names a disposable dest (see below). |
| `chat` | basic, `profile: :auto`, hooks | `format:` (`"json"` or tiny schema hash), `options:` via [`Ollama::Options`](lib/ollama/options.rb), explicit `stream: true` / `stream: false`, `keep_alive:` (e.g. `"0"` or `"1m"`), `profile: false` / `:none` path, hooks **`on_complete`** (and **`on_tool_call`** when tools-capable model available). |
| `chat` advanced | — | **`logprobs` / `top_logprobs`** when `Capabilities.for` / server supports; otherwise SKIP. **`tools:`** + forced tool-use prompt when `tools` capability true (use `OLLAMA_TOOLS_MODEL` override or primary if capable). **`inputs:`** multimodal beyond text-only when **`OLLAMA_VISION_MODEL`** set (tiny valid base64 PNG). **`think:`** on API-native thinking models when capability says `thinking` (separate from Gemma adapter path: e.g. `OLLAMA_THINKING_MODEL` or reuse Gemma env). |
| `generate` | plain, schema, stream | `system:`, `return_meta: true`, `options:` / `Ollama::Options`, `keep_alive:`, **`think:` + `return_reasoning: true`** when thinking-capable model env set; hooks **`on_complete`**; optional **`images:`** with vision model env. **`suffix:` / `raw:`** as SKIP-by-default unless a dedicated env enables FIM/raw smoke (many models ignore or error). |
| `embed` | single string | **Batch** `input: %w[a b]`; optional `truncate:` / `dimensions:` / `keep_alive:` when embed model supports (SKIP on 4xx). |
| `Response` | `content`, `usage` | Assert **`done?`**, **`model`**, **`message`**.**`role`**, numeric timing fields present when Ollama returns them (tolerate nils where API omits). |
| `history_sanitizer` | model name | Second check: pass a **`ModelProfile`** instance + **`trace_store: []`** if API supports. |
| `Capabilities` | via list entry | Explicit **`Ollama::Capabilities.for(show_model_payload)`** vs list entry parity smoke. |
| Library helpers | fragment happy path | **`JsonFragmentExtractor`** blank input → expect **`Ollama::InvalidJSONError`**; **`Ollama::SchemaValidator.validate!`** happy path on a trivial schema+data (no HTTP). |
| `OllamaClient` global | — | Optional one-liner: `OllamaClient.config` read + building a client from duplicated config (read-only; documents global entry without mutation races). |
| Destructive / network-heavy | — | **No default** `pull` / `push_model` / `create_model`. Gate: `OLLAMA_LIVE_SMOKE_COPY_TEST=1` with `OLLAMA_COPY_SOURCE` + `OLLAMA_COPY_DEST` (unique dest), then `delete_model(model: dest)` in `ensure` cleanup; SKIP if unset. |

## Implementation shape

1. **Keep a single runner class** in [`script/live_branch_smoke.rb`](script/live_branch_smoke.rb) initially; if the file crosses ~400–500 lines, extract private helpers into `script/live_smoke/helpers.rb` (optional refactor in same PR).
2. **Shared helpers:** `capabilities_for(client, model_name)`, `thinking_model_for(...)`, `vision_model_for(...)`, `embed_model_for(...)` — centralize SKIP messages.
3. **Ordering:** Run read-only management (`show`, `ps`, names) before generation-heavy checks to warm server consistently.
4. **Header comment:** Document new env vars (`OLLAMA_TOOLS_MODEL`, `OLLAMA_VISION_MODEL`, `OLLAMA_THINKING_MODEL`, copy/delete gate, optional `OLLAMA_LIVE_SMOKE_ENABLE_RAW_SUFFIX=1`, etc.).
5. **Docs (only if you want):** Sync bullet list in [`docs/INTEGRATION_TESTING.md`](docs/INTEGRATION_TESTING.md) — skip if you prefer script header only.

## Risks

- **Logprobs / tools / vision** vary by Ollama version and model: must catch errors and SKIP with explicit reason, never fail the whole suite for optional features.
- **Copy/delete** can leave garbage models on failure: use timestamped destination and `ensure` delete.
- **Thinking on non-thinking models** raises `UnsupportedThinkingModel`: gate on `Capabilities.for` before calling.

## Verification (after implementation)

- `bundle exec rubocop script/live_branch_smoke.rb` (and any new helper file)
- `bundle exec ruby script/live_branch_smoke.rb` against local Ollama (expect more PASS with extra models; baseline machine without optional models should still exit 0 with SKIPs)

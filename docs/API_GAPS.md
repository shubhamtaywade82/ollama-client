# Gaps: Ollama REST API vs ollama-client Gem

Comparison against the [Ollama API Reference](https://ollama.readthedocs.io/en/api/). The Postman collection at `c:\Users\shubh\Downloads\Ollama REST API.postman_collection.json` was not in the workspace; add it to the repo to diff against it as well.

---

## 1. Blob API — **Not implemented**

The API defines two blob endpoints for remote model creation:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/blobs/:digest` | HEAD | Check if a blob exists (200 vs 404) |
| `/api/blobs/:digest` | POST | Create a blob (upload file; returns server path) |

**Gap:** No `blob_exists?(digest)` or `create_blob(digest, file)` in the gem. Required for remote create when using `FROM`/`ADAPTER` with blobs.

---

## 2. Create Model — **Parameter mismatch**

**API parameters:** `model`, `modelfile` (optional), `path` (optional), `stream`, `quantize`.

**Gem:** `create_model(model:, from:, system:, template:, license:, parameters:, messages:, quantize:, stream:)` and sends `from` (+ system, template, etc.) in the JSON body.

- The reference docs do not list `from`, `system`, or `template` as top-level create parameters; they describe passing **modelfile content** or a **path** to a Modelfile.
- If the Ollama server accepts `from` as a shorthand for a minimal modelfile, the gem may work but is undocumented in the official API.
- **Gaps:**
  - No way to pass raw **modelfile** string (full Modelfile content).
  - No way to pass **path** (path to a Modelfile on the server).

**Recommendation:** Add optional `modelfile:` and `path:` to `create_model`. If `modelfile` or `path` is present, use that; otherwise keep building from `from` + system/template for backward compatibility (and document that behavior).

---

## 3. Pull — **Missing parameters**

**API parameters:** `model`, `stream` (optional), `insecure` (optional).

**Gem:** `pull(model_name)` — always sends `stream: false` and does not accept `insecure` or `stream`.

**Gaps:**
- No `insecure:` option (e.g. for pulling from a custom/self-hosted registry).
- No choice of streaming vs non-streaming; callers cannot get progress via stream.

**Recommendation:** Add `pull(model_name, stream: false, insecure: false)` and pass them through.

---

## 4. Generate — **Context (conversational memory)**

**API:** `/api/generate` accepts optional `context` (from a previous response) and returns `context` in the response for use in the next request.

**Gem:** `generate` does not accept or return `context`. Multi-turn “memory” is only via chat, not via generate.

**Gap:** No support for generate-side context for short conversational memory when using the generate endpoint.

**Recommendation:** Optional `context:` argument and returning `context` in metadata when `return_meta: true` (or a dedicated accessor) would align with the API.

---

## 5. Generate / Chat — **Options coverage**

**API (Modelfile/options):** The docs list many options, including at least:

- `min_p`
- `penalize_newline`
- `repeat_last_n`
- `numa`
- `num_batch`
- `main_gpu`
- `low_vram`
- `vocab_only`
- `use_mmap`
- `use_mlock`

**Gem:** `Ollama::Options` supports: `temperature`, `top_p`, `top_k`, `num_ctx`, `repeat_penalty`, `seed`, `num_predict`, `stop`, `tfs_z`, `mirostat`, `mirostat_tau`, `mirostat_eta`, `num_gpu`, `num_thread`, `num_keep`, `typical_p`, `presence_penalty`, `frequency_penalty`.

**Gap:** Options such as `min_p`, `penalize_newline`, `repeat_last_n`, `numa`, `num_batch`, `main_gpu`, `low_vram`, `vocab_only`, `use_mmap`, `use_mlock` are not in the type-safe Options class. They can still be passed as a raw hash via `options:`, so behavior is only a **documentation/consistency** gap.

**Recommendation:** Either extend `Ollama::Options` with these keys (and document which are server-dependent) or explicitly document that arbitrary option hashes are allowed and list the known API options in the yardocs.

---

## 6. Push — **Streaming behavior**

**API:** Supports `stream: true` (default) or `stream: false` with a single final JSON object.

**Gem:** `push_model(model:, insecure: false, stream: false)` — implements both parameters. When `stream: true`, the current implementation uses a single `http_request` and `JSON.parse(res.body)`, which is wrong for streaming NDJSON.

**Gap:** For `stream: true`, the gem would need to read the response body as a stream (NDJSON) and yield or return status updates, similar to pull/generate streaming. Currently only non-streaming push is correct.

---

## 7. Pull — **Streaming behavior**

**API:** Pull can stream progress (default) or return a single object when `stream: false`.

**Gem:** Always sends `stream: false` and parses a single JSON object. No streaming pull.

**Gap:** No API to get pull progress (e.g. status, digest, total, completed) via streaming. This is a **feature** gap, not a wrong-call gap.

---

## 8. Chat — **Tool message role**

**API:** Message object may have `role`: `system` | `user` | `assistant` | `tool`. Tool results are sent as messages with `role: "tool"`.

**Gem:** Response wrapper and tool_calls handling are in place; no gap identified for normal tool use. If the client ever needs to **send** tool results back (e.g. in a follow-up request), the message format with `role: "tool"` should be documented or helpers provided. Not a missing endpoint, but worth documenting for agent loops.

---

## 9. Embeddings — **Legacy endpoint**

**API:** Documents both `/api/embed` (current) and `/api/embeddings` (superseded).

**Gem:** Uses `/api/embed` only. No gap.

---

## 10. Load / Unload model (explicit)

**API:** Describes loading by calling generate/chat with empty prompt (and optional `keep_alive`), and unload with empty prompt + `keep_alive: 0`.

**Gem:** No dedicated `load_model` or `unload_model` helpers. Callers can do the same by calling `generate(prompt: "", ...)` or `chat(messages: [], ...)` with `keep_alive`.

**Gap:** Convenience only — optional helpers could reduce confusion and document the pattern.

---

## Summary table

| Area              | Severity   | Gap |
|-------------------|------------|-----|
| Blob API          | High       | HEAD/POST blobs not implemented |
| Create model      | Medium     | No raw `modelfile` or `path`; uses `from` only |
| Pull              | Medium     | No `insecure` or `stream`; no streaming progress |
| Push              | Low        | `stream: true` not implemented as real streaming |
| Generate context  | Low        | No `context` in/out for conversational memory |
| Options           | Low        | Several Modelfile options not in `Ollama::Options` |
| Load/Unload       | Optional   | No convenience methods for load/unload |

Implementing **Blob API** and **Create model (modelfile/path)** would fully align the gem with the documented API for model creation. **Pull (insecure + stream)** and **Generate context** are the next most useful for parity and agent use cases.

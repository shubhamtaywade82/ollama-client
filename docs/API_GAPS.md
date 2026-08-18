# Gaps: Ollama REST API vs ollama-client Gem

Original comparison against the [Ollama API Reference](https://ollama.readthedocs.io/en/api/). All 10
items identified below have since been closed. This file is kept for history; the actively maintained
gap tracker is [`docs/RUBYLLM_ADOPTION_MATRIX.md`](RUBYLLM_ADOPTION_MATRIX.md) section K.

| # | Area | Original gap | Status |
|---|---|---|---|
| 1 | Blob API | No `blob_exists?`/`create_blob` | **Resolved** — `Client::ModelManagement#blob_exists?(digest:)`, `#create_blob(digest:, content:)` |
| 2 | Create model | No raw `modelfile`/`path` | **Resolved** — `create_model(model:, from:, modelfile:, path:, ...)` |
| 3 | Pull | No `insecure`/`stream` | **Resolved** — `pull(model_name, insecure:, stream:, hooks:)` |
| 4 | Generate context | No `context` in/out | **Resolved** — `generate(prompt:, context:, ...)`, context returned via `return_meta:` |
| 5 | Options coverage | Missing `min_p`, `penalize_newline`, `repeat_last_n`, `numa`, `num_batch`, `main_gpu`, `low_vram`, `vocab_only`, `use_mmap`, `use_mlock` | **Resolved** — all present on `Ollama::Options` |
| 6 | Push streaming | `stream: true` not real NDJSON streaming | **Resolved** — `push_model` streams via `handle_ndjson_stream` + `hooks[:on_progress]` |
| 7 | Pull streaming | No streaming progress | **Resolved** — same mechanism as push |
| 8 | Tool message role | No `role: "tool"` helper for follow-up requests | **Resolved** — `Ollama::Agent::Messages#tool_result` (`lib/ollama/agent/messages.rb`) |
| 9 | Embeddings legacy endpoint | n/a | No gap — `/api/embed` is the current documented endpoint; `/api/embeddings` is Ollama's deprecated alias |
| 10 | Load/unload convenience | No dedicated helpers | **Resolved** — `load_model(model:, keep_alive:)`, `unload_model(model:)` |

See `API_CONTRACT.md` for the current signatures of all methods above.

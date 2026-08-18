# VCR cassettes

Real Ollama Cloud (`https://ollama.com`) HTTP interactions, recorded once and replayed on every
subsequent `bundle exec rspec` run. No network access and no `OLLAMA_API_KEY` are needed to run the
suite — only to (re-)record.

## Why cassettes exist alongside `stub_request`

`spec/ollama/vcr/*.rb` exercises the client against **real, unedited model output** — genuine
tool-call payloads, genuine `thinking` text, genuine markdown-fenced JSON, genuine (or absent)
`context` arrays — instead of hand-written response bodies. This catches drift between what the gem
assumes Ollama returns and what it actually returns.

The rest of the suite (`spec/ollama/*_spec.rb`) keeps using `stub_request` from WebMock. That's
deliberate, not legacy: WebMock stubs are how this suite exercises paths a real server can't
authentically produce on demand — timeouts, connection failures, malformed JSON, HTTP 401/404/503,
retry exhaustion — and how it asserts an exact, deterministic request/response shape (a fixed
`total_duration`, a fixed `done_reason`, etc.) for regression protection. Neither of those is
what VCR is for. See `CLAUDE.md`: "All HTTP calls must be mockable with WebMock" still holds —
VCR is `hook_into :webmock` under the hood, so a cassette *is* a (pre-recorded) WebMock stub.

## Scope: what's recordable at all

Ollama Cloud only implements a subset of the full Ollama API for a regular account/API key:

| Recordable against Cloud | Not recordable — stays on `stub_request` |
|---|---|
| `chat`, `generate` (incl. tools, `think:`, `format:`/`schema:`, streaming) | `embeddings.embed` — Cloud's catalog has no embedding models |
| `list_models`, `show_model`, `version` | `pull`, `push_model`, `create_model`, `delete_model`, `copy_model`, `create_blob` — Cloud returns `{"error":"unauthorized"}` for all of these; they're local-server-only operations |
| `web_search`, `web_fetch` | `list_running` / `ps` — same, local-server-only |

If Ollama Cloud ever opens up model-management or embeddings for API keys, the corresponding
`stub_request`-based tests are candidates to gain a VCR counterpart too.

## Re-recording

```bash
OLLAMA_API_KEY=<your Ollama Cloud key> VCR_RECORD=1 bundle exec rspec spec/ollama/vcr/
```

`VCR_RECORD=1` sets the record mode to `:once` — it records a cassette that doesn't exist yet, but
never re-records one that's already there (so a stray run without deleting a file first can't
silently change committed fixtures). To force a fresh recording for one scenario, delete its
cassette file first.

Without `VCR_RECORD`, the record mode is `:none`: a missing or non-matching cassette raises
`VCR::Errors::UnhandledHTTPRequestError` instead of silently hitting the network. This is what CI
runs, and what `OLLAMA_API_KEY`-less contributors run.

## Model choice

Cassettes are recorded against `gpt-oss:20b` (`VCRClientHelper::CLOUD_MODEL` in
`spec/support/vcr_client_helper.rb`) — a Cloud-hosted model with tool-calling and thinking support,
small enough to keep recording fast.

## Secrets

`spec/support/vcr.rb` filters the `Authorization` header (`Bearer <key>`) to the literal string
`<OLLAMA_API_KEY>` before a cassette is ever written to disk. Verify this yourself after recording
new cassettes: `grep -rn "Authorization" -A1 spec/cassettes/ | grep -v OLLAMA_API_KEY` should print
nothing.

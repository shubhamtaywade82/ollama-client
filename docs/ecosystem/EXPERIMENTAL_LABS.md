# Experimental Labs Policy

## Principle

Experiment there, stabilize here.

## Roles

| Repository | Role |
|---|---|
| `ollama-client` | Stable runtime kernel and canonical contract owner |
| `ollama_agent` | Orchestration experimentation |
| `agent-runtime` | Execution/runtime experimentation |

## Not owned by experimental repos

- transport contracts
- stream semantics
- retry semantics
- response models
- schema runtime semantics
- observability semantics

These are canonicalized in `ollama-client`.

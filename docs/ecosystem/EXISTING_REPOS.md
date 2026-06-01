# Existing Repositories and Contract Ownership

This ecosystem uses existing repos as **experimental proving grounds**, not canonical runtime authorities.

## Role Mapping

| Repository | Primary Role | Reusable Concepts | Must NOT Own |
|---|---|---|---|
| `ollama-client` | Canonical runtime kernel | transport contracts, stream semantics, error taxonomy, schema contracts, observability hooks | n/a |
| `ollama_agent` | Orchestration experimentation | planner patterns, tool execution loops, memory interface ideas | transport contracts, stream/runtime semantics, error taxonomy |
| `agent-runtime` | Higher-level execution runtime | lifecycle orchestration, scheduling concepts, workflow state transitions | inference transport, canonical response/error contracts |

## Dependency Direction

```text
ollama-client
  ↑
ollama-openai
  ↑
ollama-agent
  ↑
agent-runtime
```

Disallowed:
- `ollama-client` depending on orchestration/runtime repos.
- Upstream repos owning low-level inference contracts.

## Rule

Experiment in higher-level repos, then stabilize and standardize contracts in `ollama-client`.

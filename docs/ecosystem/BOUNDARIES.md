# Ecosystem Boundaries

## Belongs in `ollama-client`

- transport
- streaming contracts/runtime
- retries/policy orchestration
- schema/runtime contracts
- model lifecycle
- observability hooks

## Must stay out of `ollama-client`

- vector DB integrations
- RAG pipelines
- memory systems
- workflow engines
- chain builders
- prompt template frameworks

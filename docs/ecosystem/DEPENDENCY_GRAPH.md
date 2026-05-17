# Dependency Graph

Allowed direction:

`ollama-client` <- extensions

Examples:
- `ollama-openai` -> `ollama-client`
- `ollama-agent` -> `ollama-client`
- `ollama-rails` -> `ollama-client`

Disallowed:
- `ollama-client` -> any extension
- circular extension dependencies

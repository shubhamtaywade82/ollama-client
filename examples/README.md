# Examples

This directory contains **minimal examples** demonstrating `ollama-client` usage. These examples focus on **transport and protocol correctness**, not agent behavior.

## Minimal Examples

### Basic Client Usage

- **[basic_generate.rb](basic_generate.rb)** - Basic `/generate` usage with schema validation
  - Demonstrates stateless, deterministic JSON output
  - Shows schema enforcement
  - No agent logic

- **[basic_chat.rb](basic_chat.rb)** - Basic `/chat` usage
  - Demonstrates stateful message handling
  - Shows multi-turn conversation structure
  - No agent loops

- **[tool_calling_parsing.rb](tool_calling_parsing.rb)** - Tool-call parsing (no execution)
  - Demonstrates tool-call detection and extraction
  - Shows how to parse tool calls from LLM response
  - **Does NOT execute tools** - that's agent responsibility

- **[tool_dto_example.rb](tool_dto_example.rb)** - Tool DTO serialization
  - Demonstrates Tool class serialization/deserialization
  - Shows DTO functionality

- **[mcp_executor.rb](mcp_executor.rb)** - MCP tools with Executor (local stdio)
  - Connects to a local MCP server (stdio)
  - Requires Node.js/npx for the filesystem server example

- **[mcp_http_executor.rb](mcp_http_executor.rb)** - MCP tools with Executor (remote URL)
  - Connects to a remote MCP server via HTTP (e.g. [gitmcp.io](https://gitmcp.io)/owner/repo)
  - Use the same URL you would add to Cursor’s `mcp.json`

## Running Examples

All examples are standalone and can be run directly:

```bash
# Basic generate
ruby examples/basic_generate.rb

# Basic chat
ruby examples/basic_chat.rb

# Tool calling parsing
ruby examples/tool_calling_parsing.rb

# Tool DTO
ruby examples/tool_dto_example.rb

# MCP Executor (local stdio; requires Node.js/npx)
ruby examples/mcp_executor.rb

# MCP Executor (remote URL, e.g. GitMCP)
ruby examples/mcp_http_executor.rb
```

### Requirements

- Ollama server running (default: `http://localhost:11434`)
- Set `OLLAMA_BASE_URL` if using a different URL
- Set `OLLAMA_MODEL` if not using default model

## Full Agent Examples

For complete agent examples (trading agents, coding agents, RAG agents, multi-step workflows, tool execution patterns, etc.), see:

**[ollama-agent-examples](https://github.com/shubhamtaywade82/ollama-agent-examples)**

This separation keeps `ollama-client` focused on the transport layer while providing comprehensive examples for agent developers.

## What These Examples Demonstrate

These minimal examples prove:

✅ **Transport layer** - HTTP requests/responses  
✅ **Protocol correctness** - Request shaping, response parsing  
✅ **Schema enforcement** - JSON validation  
✅ **Tool-call parsing** - Detecting and extracting tool calls  

These examples do **NOT** demonstrate:

❌ Agent loops  
❌ Tool execution  
❌ Convergence logic  
❌ Policy decisions  
❌ Domain-specific logic  

**Those belong in the separate agent examples repository.**

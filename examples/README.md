# Examples

This directory contains working examples demonstrating various features of the ollama-client gem.

## Quick Start Examples

### Basic Tool Calling
- **[test_tool_calling.rb](test_tool_calling.rb)** - Simple tool calling demo with weather tool
- **[tool_calling_pattern.rb](tool_calling_pattern.rb)** - Recommended patterns for tool calling
- **[tool_calling_direct.rb](tool_calling_direct.rb)** - Direct tool calling without Executor

### DhanHQ Market Data
- **[test_dhanhq_tool_calling.rb](test_dhanhq_tool_calling.rb)** - DhanHQ tools with updated intraday & indicators
- **[dhanhq_tools.rb](dhanhq_tools.rb)** - DhanHQ API wrapper tools
- **[dhan_console.rb](dhan_console.rb)** - Interactive DhanHQ console with planning

### Multi-Step Agents
- **[multi_step_agent_e2e.rb](multi_step_agent_e2e.rb)** - End-to-end multi-step agent example
- **[multi_step_agent_with_external_data.rb](multi_step_agent_with_external_data.rb)** - Agent with external data integration

### Structured Data
- **[structured_outputs_chat.rb](structured_outputs_chat.rb)** - Structured outputs with schemas
- **[structured_tools.rb](structured_tools.rb)** - Structured tool definitions
- **[tool_dto_example.rb](tool_dto_example.rb)** - Using DTOs for tool definitions

### Advanced Features
- **[advanced_multi_step_agent.rb](advanced_multi_step_agent.rb)** - Complex multi-step workflows
- **[advanced_error_handling.rb](advanced_error_handling.rb)** - Error handling patterns
- **[advanced_edge_cases.rb](advanced_edge_cases.rb)** - Edge case handling
- **[advanced_complex_schemas.rb](advanced_complex_schemas.rb)** - Complex schema definitions
- **[advanced_performance_testing.rb](advanced_performance_testing.rb)** - Performance testing

### Interactive Consoles
- **[chat_console.rb](chat_console.rb)** - Simple chat console with streaming
- **[dhan_console.rb](dhan_console.rb)** - DhanHQ market data console with formatted tool results

### Complete Workflows
- **[complete_workflow.rb](complete_workflow.rb)** - Complete agent workflow example

## DhanHQ Examples

The `dhanhq/` subdirectory contains more specialized DhanHQ examples:
- Technical analysis agents
- Market scanners (intraday options, swing trading)
- Pattern recognition and trend analysis
- Multi-agent orchestration

See [dhanhq/README.md](dhanhq/README.md) for details.

## Running Examples

Most examples are standalone and can be run directly:

```bash
# Basic tool calling
ruby examples/test_tool_calling.rb

# DhanHQ with intraday data
ruby examples/test_dhanhq_tool_calling.rb

# Interactive console
ruby examples/chat_console.rb
```

### Requirements

Some examples require additional setup:

**DhanHQ Examples:**
- Set `DHANHQ_CLIENT_ID` and `DHANHQ_ACCESS_TOKEN` environment variables
- Or create `.env` file with credentials

**Ollama:**
- Ollama server running (default: `http://localhost:11434`)
- Set `OLLAMA_BASE_URL` if using a different URL
- Set `OLLAMA_MODEL` if not using default model

## Learning Path

1. **Start here:** `test_tool_calling.rb` - Learn basic tool calling
2. **Structured data:** `structured_outputs_chat.rb` - Schema-based outputs
3. **Multi-step:** `multi_step_agent_e2e.rb` - Complex agent workflows
4. **Market data:** `test_dhanhq_tool_calling.rb` - Real-world API integration
5. **Interactive:** `dhan_console.rb` - Full-featured console with planning

## Contributing

When adding new examples:
- Include clear comments explaining what the example demonstrates
- Add `#!/usr/bin/env ruby` shebang at the top
- Use `frozen_string_literal: true`
- Update this README with a description

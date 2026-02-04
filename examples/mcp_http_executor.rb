# frozen_string_literal: true

# Example: Use a remote MCP server (HTTP URL) with Ollama::Agent::Executor.
#
# Works with GitMCP and any MCP-over-HTTP endpoint:
#   https://gitmcp.io/owner/repo  → MCP server for that GitHub repo
#
# Prerequisites:
#   - Ollama running (localhost:11434)
#   - Network access to the MCP URL
#
# Run:
#   ruby examples/mcp_http_executor.rb
#
# To add this MCP to Cursor, use ~/.cursor/mcp.json:
#   {
#     "mcpServers": {
#       "agent-runtime Docs": {
#         "url": "https://gitmcp.io/shubhamtaywade82/agent-runtime"
#       }
#     }
#   }

require "ollama_client"

client = Ollama::Client.new

mcp_client = Ollama::MCP::HttpClient.new(
  url: "https://gitmcp.io/shubhamtaywade82/agent-runtime",
  timeout_seconds: 60
)

bridge = Ollama::MCP::ToolsBridge.new(client: mcp_client)
tools = bridge.tools_for_executor

executor = Ollama::Agent::Executor.new(client, tools: tools)

answer = executor.run(
  system: "You have access to the agent-runtime repository docs. Use tools when the user asks about the repo.",
  user: "What does this repository do? Summarize briefly."
)

puts answer

mcp_client.close

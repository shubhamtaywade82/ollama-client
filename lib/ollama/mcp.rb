# frozen_string_literal: true

# MCP (Model Context Protocol) support for local servers.
#
# Connect to MCP servers running via stdio (e.g. npx @modelcontextprotocol/server-filesystem)
# and use their tools with Ollama::Agent::Executor.
#
# Example (remote URL, e.g. GitMCP):
#   mcp_client = Ollama::MCP::HttpClient.new(url: "https://gitmcp.io/owner/repo")
#   bridge = Ollama::MCP::ToolsBridge.new(client: mcp_client)
#   tools = bridge.tools_for_executor
#   executor = Ollama::Agent::Executor.new(ollama_client, tools: tools)
#   executor.run(system: "...", user: "What does this repo do?")
#
# Example (local stdio):
#   mcp_client = Ollama::MCP::StdioClient.new(
#     command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
#   )
#   bridge = Ollama::MCP::ToolsBridge.new(stdio_client: mcp_client)
#   tools = bridge.tools_for_executor
#   executor.run(system: "...", user: "List files in /tmp")
#
module Ollama
  # Model Context Protocol client and tools bridge for Executor.
  module MCP
  end
end

require_relative "mcp/stdio_client"
require_relative "mcp/http_client"
require_relative "mcp/tools_bridge"

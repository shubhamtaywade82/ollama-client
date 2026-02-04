# frozen_string_literal: true

# Example: Use a local MCP server's tools with Ollama::Agent::Executor.
#
# Prerequisites:
#   - Ollama running (localhost:11434)
#   - Node.js/npx (for @modelcontextprotocol/server-filesystem)
#
# Run:
#   ruby examples/mcp_executor.rb
#
# This connects to the MCP filesystem server, fetches its tools, and runs
# the Executor so the LLM can call those tools (e.g. list directory, read file).

require_relative "../lib/ollama_client"

ollama = Ollama::Client.new

# Local MCP server via stdio; allow /tmp and the project directory
project_root = File.expand_path("..", __dir__)
mcp_client = Ollama::MCP::StdioClient.new(
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp", project_root],
  timeout_seconds: 60
)

bridge = Ollama::MCP::ToolsBridge.new(stdio_client: mcp_client)
tools = bridge.tools_for_executor

executor = Ollama::Agent::Executor.new(ollama, tools: tools)

answer = executor.run(
  system: "You have access to filesystem tools. Use them when the user asks about files or directories.",
  user: "What files are in  ~/project/ollama-client? List a few."
)

puts answer

mcp_client.close

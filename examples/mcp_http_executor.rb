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

require_relative "../lib/ollama_client"

client = Ollama::Client.new

mcp_client = Ollama::MCP::HttpClient.new(
  url: "https://gitmcp.io/shubhamtaywade82/agent-runtime",
  timeout_seconds: 60
)

bridge = Ollama::MCP::ToolsBridge.new(client: mcp_client)
tools = bridge.tools_for_executor

# Wrap tools with simple logging so you can SEE HTTP MCP tool calls in the terminal.
logged_tools = tools.each_with_object({}) do |(name, entry), hash|
  callable = entry[:callable]
  hash[name] = {
    tool: entry[:tool],
    callable: lambda do |**kwargs|
      warn "[MCP HTTP TOOL] #{name}(#{kwargs.inspect})"
      callable.call(**kwargs)
    end
  }
end

executor = Ollama::Agent::Executor.new(client, tools: logged_tools)

answer = executor.run(
  system: "You have access to MCP tools for the agent-runtime repository. " \
          "When the user asks about the repo or its files, you MUST invoke tools " \
          "via the function-calling interface. Never just print JSON that looks " \
          "like a tool call; that will not be executed.",
  user: "What does this repository do? Summarize briefly using the MCP tools instead of guessing."
)

puts answer

mcp_client.close

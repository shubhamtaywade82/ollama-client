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

# Wrap tools with simple logging so you can SEE tool calls in the terminal.
logged_tools = tools.each_with_object({}) do |(name, entry), hash|
  callable = entry[:callable]
  hash[name] = {
    tool: entry[:tool],
    callable: ->(**kwargs) do
      warn "[MCP TOOL] #{name}(#{kwargs.inspect})"
      callable.call(**kwargs)
    end
  }
end

executor = Ollama::Agent::Executor.new(ollama, tools: logged_tools)

answer = executor.run(
  system: "You have access to filesystem tools for this Ruby project. " \
          "When you need information about files or directories, you MUST " \
          "invoke a tool call via the function-calling interface. " \
          "Never just print JSON that looks like a tool call; that will not be executed.",
  user: "Find the README for this project and summarize: (1) what this gem does and " \
        "(2) how to install and run its test suite. Use the filesystem tools instead of guessing."
)

puts answer

mcp_client.close

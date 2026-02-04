# frozen_string_literal: true

require_relative "../tool"

module Ollama
  module MCP
    # Bridges an MCP server's tools to Ollama::Agent::Executor.
    # Fetches tools via tools/list, converts them to Ollama tool format,
    # and provides a callable per tool that invokes tools/call.
    # Accepts either client: (StdioClient or HttpClient) or stdio_client: for backward compatibility.
    class ToolsBridge
      def initialize(stdio_client: nil, client: nil)
        @client = client || stdio_client
        raise ArgumentError, "Provide client: or stdio_client:" unless @client

        @tools_cache = nil
      end

      # Returns a hash suitable for Executor: name => { tool: Ollama::Tool, callable: proc }.
      # Callable receives keyword args and returns a string (tool result for the LLM).
      def tools_for_executor
        fetch_tools unless @tools_cache

        @tools_cache.transform_values do |entry|
          {
            tool: entry[:tool],
            callable: build_callable(entry[:name])
          }
        end
      end

      # Returns raw MCP tool list (name, description, input_schema).
      def list_tools
        @client.tools
      end

      private

      def fetch_tools
        list = @client.tools
        @tools_cache = list.each_with_object({}) do |mcp_tool, hash|
          name = mcp_tool[:name]
          next if name.nil? || name.to_s.empty?

          hash[name.to_s] = {
            name: name.to_s,
            tool: mcp_tool_to_ollama(mcp_tool)
          }
        end
      end

      def mcp_tool_to_ollama(mcp_tool)
        schema = mcp_tool[:input_schema] || { "type" => "object" }
        function_hash = {
          "name" => mcp_tool[:name].to_s,
          "description" => (mcp_tool[:description] || "MCP tool: #{mcp_tool[:name]}").to_s,
          "parameters" => schema
        }
        Ollama::Tool.from_hash("type" => "function", "function" => function_hash)
      end

      def build_callable(name)
        client = @client
        ->(**kwargs) { client.call_tool(name: name, arguments: stringify_keys(kwargs)) }
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end

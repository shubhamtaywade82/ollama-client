# frozen_string_literal: true

require "json"
require "open3"

module Ollama
  module MCP
    # Connects to a local MCP server via stdio (spawns subprocess).
    # Handles JSON-RPC lifecycle: initialize, tools/list, tools/call.
    class StdioClient
      PROTOCOL_VERSION = "2025-11-25"

      def initialize(command:, args: [], env: {}, timeout_seconds: 30)
        @command = command
        @args = Array(args)
        @env = env
        @timeout = timeout_seconds
        @request_id = 0
        @reader = nil
        @writer = nil
        @initialized = false
      end

      def start
        return if @initialized

        env_merged = ENV.to_h.merge(@env.transform_keys(&:to_s))
        stdin, stdout = Open3.popen2(env_merged, @command, *@args)
        @writer = stdin
        @reader = stdout
        run_initialize
        @initialized = true
      end

      def tools
        start
        response = request("tools/list", {})
        list = response.dig("result", "tools")
        return [] unless list.is_a?(Array)

        list.map do |t|
          {
            name: (t["name"] || t[:name]).to_s,
            description: (t["description"] || t[:description]).to_s,
            input_schema: t["inputSchema"] || t[:input_schema] || { "type" => "object" }
          }
        end
      end

      def call_tool(name:, arguments: {})
        start
        response = request("tools/call", "name" => name.to_s, "arguments" => stringify_keys(arguments))
        result = response["result"]
        raise Ollama::Error, "tools/call failed: #{response["error"]}" if response["error"]
        raise Ollama::Error, "tools/call returned no result" unless result

        content_to_string(result["content"])
      end

      def close
        return unless @writer

        @writer.close
        @writer = nil
        @reader = nil
        @initialized = false
      end

      private

      def run_initialize
        init_params = {
          "protocolVersion" => PROTOCOL_VERSION,
          "capabilities" => {},
          "clientInfo" => {
            "name" => "ollama-client",
            "version" => Ollama::VERSION
          }
        }
        response = request("initialize", init_params)
        raise Ollama::Error, "initialize failed: #{response["error"]}" if response["error"]

        send_notification("notifications/initialized", {})
      end

      def next_id
        @request_id += 1
      end

      def request(method, params)
        id = next_id
        msg = { "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params }
        send_message(msg)
        wait_for_response(id)
      end

      def send_notification(method, params)
        send_message("jsonrpc" => "2.0", "method" => method, "params" => params)
      end

      def send_message(msg)
        line = "#{JSON.generate(msg)}\n"
        @writer.write(line)
        @writer.flush
      end

      def wait_for_response(expected_id)
        loop do
          line = read_line_with_timeout
          next if line.nil? || line.strip.empty?
          next unless line.strip.start_with?("{")

          parsed = JSON.parse(line)
          next if parsed["method"] # notification from server

          return parsed if parsed["id"] == expected_id
        end
      end

      def read_line_with_timeout
        unless @reader.wait_readable(@timeout)
          raise Ollama::TimeoutError, "MCP server did not respond within #{@timeout}s"
        end

        @reader.gets
      end

      def stringify_keys(hash)
        return {} if hash.nil?

        hash.transform_keys(&:to_s)
      end

      def content_to_string(content)
        return "" unless content.is_a?(Array)

        content.filter_map do |item|
          next unless item.is_a?(Hash)

          text = item["text"] || item[:text]
          text&.to_s
        end.join("\n")
      end
    end
  end
end

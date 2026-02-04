# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Ollama
  module MCP
    # Connects to a remote MCP server via HTTP(S).
    # Sends JSON-RPC via POST; supports session ID from initialize response.
    # Use for URLs like https://gitmcp.io/owner/repo.
    class HttpClient
      PROTOCOL_VERSION = "2025-11-25"

      def initialize(url:, timeout_seconds: 30, headers: {})
        @uri = URI(url)
        @uri.path = "/" if @uri.path.nil? || @uri.path.empty?
        @timeout = timeout_seconds
        @extra_headers = headers.transform_keys(&:to_s)
        @request_id = 0
        @session_id = nil
        @initialized = false
      end

      def start
        return if @initialized

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
        @session_id = nil
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
        post_request(msg, method: method)
      end

      def send_notification(method, params)
        body = { "jsonrpc" => "2.0", "method" => method, "params" => params }
        post_request(body, method: method)
      end

      def post_request(body, method: nil)
        req = Net::HTTP::Post.new(@uri)
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json, text/event-stream"
        req["MCP-Protocol-Version"] = PROTOCOL_VERSION
        req["MCP-Session-Id"] = @session_id if @session_id
        @extra_headers.each { |k, v| req[k] = v }
        req.body = body.is_a?(Hash) ? JSON.generate(body) : body.to_s

        res = http_request(req)

        if method == "initialize" && res["MCP-Session-Id"]
          @session_id = res["MCP-Session-Id"].to_s.strip
          @session_id = nil if @session_id.empty?
        end

        return {} if res.code == "202"

        raise Ollama::Error, "MCP HTTP error: #{res.code} #{res.message}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body)
      end

      def http_request(req)
        Net::HTTP.start(
          @uri.hostname,
          @uri.port,
          use_ssl: @uri.scheme == "https",
          read_timeout: @timeout,
          open_timeout: @timeout
        ) { |http| http.request(req) }
      rescue Net::ReadTimeout, Net::OpenTimeout
        raise Ollama::TimeoutError, "MCP server did not respond within #{@timeout}s"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        raise Ollama::Error, "MCP connection failed: #{e.message}"
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

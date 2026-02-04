# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::MCP::HttpClient do
  let(:url) { "https://gitmcp.io/owner/repo" }
  let(:client) { described_class.new(url: url, timeout_seconds: 10) }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  def stub_initialize(session_id: nil)
    response_headers = { "Content-Type" => "application/json" }
    response_headers["MCP-Session-Id"] = session_id if session_id

    stub_request(:post, url)
      .with { |req| JSON.parse(req.body).then { |b| b["method"] == "initialize" } }
      .to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
        headers: response_headers
      )
  end

  def stub_initialized
    stub_request(:post, url)
      .with { |req| JSON.parse(req.body)["method"] == "notifications/initialized" }
      .to_return(status: 202)
  end

  def stub_tools_list(tools = [])
    stub_request(:post, url)
      .with { |req| JSON.parse(req.body)["method"] == "tools/list" }
      .to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 2, result: { tools: tools } }.to_json
      )
  end

  describe "#tools" do
    it "returns tools from remote MCP server" do
      stub_initialize
      stub_initialized
      stub_tools_list([
                        { "name" => "read_docs", "description" => "Read repo docs",
                          "inputSchema" => { "type" => "object" } }
                      ])

      result = client.tools

      expect(result).to contain_exactly(
        hash_including(name: "read_docs", description: "Read repo docs", input_schema: { "type" => "object" })
      )
    end
  end

  describe "#call_tool" do
    it "invokes tool and returns content string" do
      stub_initialize
      stub_initialized
      stub_tools_list([{ "name" => "read_docs", "description" => "Read docs", "inputSchema" => {} }])

      stub_request(:post, url)
        .with do |req|
          JSON.parse(req.body)["method"] == "tools/call" && JSON.parse(req.body).dig("params",
                                                                                     "name") == "read_docs"
      end
        .to_return(
          status: 200,
          body: {
            jsonrpc: "2.0",
            id: 3,
            result: { content: [{ type: "text", text: "Doc content here" }], isError: false }
          }.to_json
        )

      client.start
      result = client.call_tool(name: "read_docs", arguments: { "path" => "/README.md" })

      expect(result).to eq("Doc content here")
    end
  end

  describe "session ID" do
    it "sends MCP-Session-Id on subsequent requests when server returns it" do
      stub_initialize(session_id: "session-123")
      stub_initialized
      stub_tools_list([])

      client.tools

      expect(WebMock).to have_requested(:post, url).with(headers: { "MCP-Session-Id" => "session-123" }).at_least_once
    end
  end
end

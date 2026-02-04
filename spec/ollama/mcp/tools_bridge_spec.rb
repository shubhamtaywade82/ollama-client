# frozen_string_literal: true

RSpec.describe Ollama::MCP::ToolsBridge do
  let(:stdio_client) do
    instance_double(Ollama::MCP::StdioClient).tap do |client|
      allow(client).to receive(:tools).and_return([
                                                    {
                                                      name: "read_file",
                                                      description: "Read a file",
                                                      input_schema: {
                                                        "type" => "object",
                                                        "properties" => { "path" => { "type" => "string",
                                                                                      "description" => "File path" } },
                                                        "required" => ["path"]
                                                      }
                                                    }
                                                  ])
      allow(client).to receive(:call_tool).with(name: "read_file", arguments: { "path" => "/tmp/foo" })
                                          .and_return("file contents here")
    end
  end

  let(:bridge) { described_class.new(stdio_client: stdio_client) }

  describe "#tools_for_executor" do
    it "returns a hash suitable for Executor" do
      tools = bridge.tools_for_executor

      expect(tools).to be_a(Hash)
      expect(tools.keys).to eq(["read_file"])
      expect(tools["read_file"]).to include(:tool, :callable)
    end

    it "exposes Ollama::Tool for each MCP tool" do
      tools = bridge.tools_for_executor
      tool_entry = tools["read_file"]

      expect(tool_entry[:tool]).to be_a(Ollama::Tool)
      expect(tool_entry[:tool].function.name).to eq("read_file")
      expect(tool_entry[:tool].function.description).to eq("Read a file")
    end

    it "callable invokes MCP client and returns string result" do
      tools = bridge.tools_for_executor
      callable = tools["read_file"][:callable]

      result = callable.call(path: "/tmp/foo")

      expect(result).to eq("file contents here")
      expect(stdio_client).to have_received(:call_tool).with(name: "read_file", arguments: { "path" => "/tmp/foo" })
    end

    context "when using client: (e.g. HttpClient)" do
      let(:bridge_with_client) { described_class.new(client: stdio_client) }

      it "returns the same tools_for_executor shape" do
        tools = bridge_with_client.tools_for_executor
        expect(tools.keys).to eq(["read_file"])
        expect(tools["read_file"]).to include(:tool, :callable)
      end
    end
  end
end

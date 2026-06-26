# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#generate_tool_intent" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
      c.retries = 0
      c.timeout = 5
    end
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  it "returns a ToolIntent with action and input" do
    stub_request(:post, "http://localhost:11434/api/generate")
      .to_return(
        status: 200,
        body: { response: '{"action":"search","input":{"query":"x"}}' }.to_json
      )

    intent = client.generate_tool_intent(
      prompt: "Find next step",
      tools: [{ name: "search", description: "Search the web" }]
    )

    expect(intent).to be_a(Ollama::ToolIntent)
    expect(intent.action).to eq("search")
    expect(intent.input).to eq("query" => "x")
    expect(intent.finish?).to be false
  end

  it "defaults input to empty object when missing" do
    stub_request(:post, "http://localhost:11434/api/generate")
      .to_return(
        status: 200,
        body: { response: '{"action":"finish"}' }.to_json
      )

    intent = client.generate_tool_intent(
      prompt: "Done",
      tools: [{ name: "search", description: "Search the web" }]
    )

    expect(intent.action).to eq("finish")
    expect(intent.input).to eq({})
    expect(intent.finish?).to be true
  end

  it "rejects hallucinated fields (schema strict)" do
    stub_request(:post, "http://localhost:11434/api/generate")
      .to_return(
        status: 200,
        body: { response: '{"action":"search","input":{},"extra":"nope"}' }.to_json
      )

    expect do
      client.generate_tool_intent(
        prompt: "Find next step",
        tools: [{ name: "search", description: "Search the web" }]
      )
    end.to raise_error(Ollama::RetryExhaustedError)
  end
end


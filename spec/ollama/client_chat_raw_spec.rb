# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#chat_raw" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
      c.retries = 1
      c.timeout = 5
    end
  end

  let(:messages) do
    [
      { role: "user", content: "Hello" }
    ]
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  it "requires explicit opt-in to use chat_raw()" do
    expect do
      client.chat_raw(messages: messages)
    end.to raise_error(Ollama::Error, /gated/i)
  end

  it "returns the full parsed response body (including tool_calls)" do
    stub_request(:post, "http://localhost:11434/api/chat")
      .to_return(
        status: 200,
        body: {
          model: "test-model",
          message: {
            role: "assistant",
            content: "Hello!",
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: { name: "fetch_weather", arguments: "{\"city\":\"Paris\"}" }
              }
            ]
          }
        }.to_json
      )

    result = client.chat_raw(messages: messages, allow_chat: true)
    expect(result.dig("message", "tool_calls")).to be_a(Array)
    expect(result.dig("message", "tool_calls", 0, "function", "name")).to eq("fetch_weather")
  end

  it "supports streaming mode by yielding chunks and returning the final parsed body" do
    chunks = []

    body = [
      { message: { role: "assistant", content: "Hello" }, done: false }.to_json,
      { message: { role: "assistant", content: " world" }, done: true }.to_json
    ].join("\n")
    body = "#{body}\n"

    stub_request(:post, "http://localhost:11434/api/chat")
      .to_return(status: 200, body: body)

    result = client.chat_raw(messages: messages, allow_chat: true, stream: true) do |chunk|
      chunks << chunk
    end

    expect(chunks.length).to eq(2)
    expect(result.dig("message", "content")).to include("Hello")
  end
end

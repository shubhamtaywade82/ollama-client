# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Agent::Executor do
  let(:client) { Ollama::Client.new(config: config) }
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

  it "runs a tool-calling loop and returns final assistant content" do
    request_bodies = []

    tool_called = false
    tools = {
      "fetch_weather" => lambda do |city:|
        tool_called = true
        { city: city, forecast: "sunny" }
      end
    }

    stub_request(:post, "http://localhost:11434/api/chat")
      .with do |req|
        request_bodies << JSON.parse(req.body)
        true
      end
      .to_return(
        {
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: "",
              tool_calls: [
                {
                  id: "call_1",
                  type: "function",
                  function: {
                    name: "fetch_weather",
                    arguments: "{\"city\":\"Paris\"}"
                  }
                }
              ]
            }
          }.to_json
        },
        {
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: "Paris will be sunny. Enjoy your trip!"
            }
          }.to_json
        }
      )

    executor = described_class.new(client, tools: tools, max_steps: 5)
    result = executor.run(system: "You are helpful.", user: "What's the weather in Paris?")

    expect(tool_called).to be(true)
    expect(result).to include("sunny")

    # First request should include tool definitions.
    expect(request_bodies.first).to have_key("tools")
    expect(request_bodies.first["tools"].first.dig("function", "name")).to eq("fetch_weather")

    # Second request should include the tool result message in history.
    tool_message = request_bodies.last["messages"].find { |m| m["role"] == "tool" }
    expect(tool_message).not_to be_nil
    expect(tool_message["tool_call_id"]).to eq("call_1")
    expect(tool_message["name"]).to eq("fetch_weather")
    expect(tool_message["content"]).to include("sunny")
  end
end


# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Agent::Planner do
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

  it "uses /api/generate and returns parsed JSON" do
    request_body = nil
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "{\"ok\":true}" }.to_json)

    planner = described_class.new(client)
    result = planner.run(prompt: "Return JSON.", context: { user: "alice" })

    expect(result).to eq("ok" => true)
    expect(request_body["prompt"]).to include("Context (JSON):")
    expect(request_body).to have_key("format")
  end
end


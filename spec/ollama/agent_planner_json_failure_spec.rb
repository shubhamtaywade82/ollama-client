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

  it "raises InvalidJSONError when the model output is not valid JSON" do
    stub_request(:post, "http://localhost:11434/api/generate")
      .to_return(status: 200, body: { response: "not json" }.to_json)

    planner = described_class.new(client)

    expect do
      planner.run(prompt: "Return JSON.")
    end.to raise_error(Ollama::InvalidJSONError)
  end
end


# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#list_models" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.timeout = 5
    end
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "successful requests" do
    it "returns array of model names" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "llama3.1:8b" },
              { name: "mistral:7b" },
              { name: "qwen2.5:7b" }
            ]
          }.to_json
        )

      models = client.list_models

      expect(models).to eq(["llama3.1:8b", "mistral:7b", "qwen2.5:7b"])
    end

    it "returns empty array when no models are available" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: { models: [] }.to_json
        )

      models = client.list_models

      expect(models).to eq([])
    end

    it "handles missing models key gracefully" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {}.to_json
        )

      models = client.list_models

      expect(models).to eq([])
    end
  end

  describe "error handling" do
    it "raises Error on HTTP failure" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 500, body: "Internal Server Error")

      expect do
        client.list_models
      end.to raise_error(Ollama::Error, /Failed to fetch models/)
    end

    it "raises InvalidJSONError on malformed JSON" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 200, body: "not json")

      expect do
        client.list_models
      end.to raise_error(Ollama::InvalidJSONError)
    end

    it "raises TimeoutError on timeout" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_timeout

      expect do
        client.list_models
      end.to raise_error(Ollama::TimeoutError)
    end

    it "raises Error on connection failure" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_raise(SocketError.new("Connection refused"))

      expect do
        client.list_models
      end.to raise_error(Ollama::Error, /Connection failed/)
    end
  end
end

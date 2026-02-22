# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client do
  it "has a version number" do
    expect(Ollama::VERSION).not_to be_nil
    expect(Ollama::VERSION).to be_a(String)
  end

  describe ".new" do
    before do
      OllamaClient.configure do |c|
        c.base_url = "http://localhost:11434"
        c.model = "llama3.2"
        c.timeout = 30
        c.retries = 2
        c.strict_json = true
        c.temperature = 0.2
        c.top_p = 0.9
        c.num_ctx = 8192
      end
    end

    it "initializes with default config" do
      client = described_class.new
      config = client.instance_variable_get(:@config)
      expect(config).to be_a(Ollama::Config)
      expect(config.model).to eq("llama3.2")
    end

    it "accepts custom config" do
      custom_config = Ollama::Config.new
      custom_config.model = "custom_model"
      client = described_class.new(config: custom_config)
      config = client.instance_variable_get(:@config)
      expect(config.model).to eq("custom_model")
    end
  end

  describe "#generate" do
    let(:client) { described_class.new(config: Ollama::Config.new) }
    let(:schema) do
      {
        "type" => "object",
        "required" => ["test"],
        "properties" => {
          "test" => { "type" => "string" }
        }
      }
    end

    it "requires prompt parameter" do
      expect { client.generate }.to raise_error(ArgumentError)
      expect { client.generate(schema: schema) }.to raise_error(ArgumentError)

      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 200, body: { response: "test response" }.to_json)
      expect { client.generate(prompt: "test") }.not_to raise_error
    end

    context "when Ollama server is not available (ECONNREFUSED)" do
      it "raises an error immediately without retrying because it is not retryable by default" do
        unavailable_client = described_class.new(config: Ollama::Config.new.tap do |c|
          c.base_url = "http://localhost:99999"
          c.retries = 3
        end)

        stub_request(:post, "http://localhost:99999/api/generate")
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))

        expect do
          unavailable_client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::Error, /Connection failed/)
      end
    end

    context "when hitting a timeout" do
      it "retries with exponential backoff and exhausts retries" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_raise(Net::ReadTimeout)
          .times(3)

        allow(client).to receive(:sleep)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::RetryExhaustedError, /timed out/)

        expect(client).to have_received(:sleep).with(2).ordered
        expect(client).to have_received(:sleep).with(4).ordered
      end
    end

    context "when hitting invalid JSON with strict mode" do
      it "appends repair prompt and retries" do
        # First request returns invalid JSON
        stub_request(:post, "http://localhost:11434/api/generate")
          .with(body: /original prompt/)
          .to_return(status: 200, body: "Not JSON")

        # Second request successfully returns JSON
        stub_request(:post, "http://localhost:11434/api/generate")
          .with(body: /CRITICAL FIX/)
          .to_return(status: 200, body: { response: '{"test":"fixed"}' }.to_json)

        result = client.generate(prompt: "original prompt", schema: schema, strict: true)
        expect(result).to eq("test" => "fixed")
      end
    end

    context "when model is missing (404)" do
      it "attempts to pull the model once then retries" do
        # First request returns 404
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 404, body: "model not found")

        # Then it should trigger a pull
        stub_request(:post, "http://localhost:11434/api/pull")
          .to_return(status: 200, body: { status: "success" }.to_json)

        # The subsequent retry returns 200
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 200, body: { response: '{"test":"value"}' }.to_json)

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: { models: [] }.to_json)

        result = client.generate(prompt: "test", schema: schema)
        expect(result).to eq("test" => "value")
      end
    end
  end
end

RSpec.describe Ollama::Config do
  describe "#initialize" do
    it "sets safe defaults" do
      config = described_class.new
      expect(config.base_url).to eq("http://localhost:11434")
      expect(config.model).to eq("llama3.2")
      expect(config.timeout).to eq(30)
      expect(config.retries).to eq(2)
      expect(config.strict_json).to be(true)
      expect(config.temperature).to eq(0.2)
      expect(config.top_p).to eq(0.9)
      expect(config.num_ctx).to eq(8192)
    end
  end
end

RSpec.describe Ollama::SchemaValidator do
  describe ".validate!" do
    it "validates data against schema" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => "test" }
      expect { described_class.validate!(data, schema) }.not_to raise_error
    end

    it "raises SchemaViolationError on invalid data" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => 123 }
      expect do
        described_class.validate!(data, schema)
      end.to raise_error(Ollama::SchemaViolationError)
    end
  end
end

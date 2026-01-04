# frozen_string_literal: true

RSpec.describe Ollama::Client do
  it "has a version number" do
    expect(Ollama::VERSION).not_to be_nil
    expect(Ollama::VERSION).to be_a(String)
  end

  describe ".new" do
    it "initializes with default config" do
      client = described_class.new
      config = client.instance_variable_get(:@config)
      expect(config).to be_a(Ollama::Config)
      expect(config.model).to eq("qwen2.5:7b")
    end

    it "accepts custom config" do
      custom_config = Ollama::Config.new
      custom_config.model = "llama3.1"
      client = described_class.new(config: custom_config)
      config = client.instance_variable_get(:@config)
      expect(config.model).to eq("llama3.1")
    end
  end

  describe "#generate" do
    let(:client) { described_class.new }
    let(:schema) do
      {
        "type" => "object",
        "required" => ["test"],
        "properties" => {
          "test" => { "type" => "string" }
        }
      }
    end

    it "requires prompt and schema parameters" do
      expect { client.generate }.to raise_error(ArgumentError)
      expect { client.generate(prompt: "test") }.to raise_error(ArgumentError)
      expect { client.generate(schema: schema) }.to raise_error(ArgumentError)
    end

    context "when Ollama server is not available" do
      it "raises an error after retries" do
        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::Error)
      end
    end
  end
end

RSpec.describe Ollama::Config do
  describe "#initialize" do
    it "sets safe defaults" do
      config = described_class.new
      expect(config.base_url).to eq("http://localhost:11434")
      expect(config.model).to eq("qwen2.5:7b")
      expect(config.timeout).to eq(20)
      expect(config.retries).to eq(2)
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

RSpec.describe OllamaClient do
  describe ".config" do
    it "returns a Config instance" do
      expect(described_class.config).to be_a(Ollama::Config)
    end

    it "returns the same instance on subsequent calls" do
      config1 = described_class.config
      config2 = described_class.config
      expect(config1).to be(config2)
    end
  end

  describe ".configure" do
    it "yields the config instance" do
      described_class.configure do |config|
        expect(config).to be_a(Ollama::Config)
        config.model = "test-model"
      end
      expect(described_class.config.model).to eq("test-model")
    end
  end
end

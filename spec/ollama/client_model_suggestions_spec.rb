# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#enhance_not_found_error" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "nonexistent-model"
    end
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "model suggestions" do
    it "suggests similar models by exact match" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "llama3.1:8b" },
              { name: "llama3.1:7b" },
              { name: "mistral:7b" }
            ]
          }.to_json
        )

      # Use a model name that will match
      config.model = "llama"

      expect do
        client.generate(prompt: "test", schema: { "type" => "object" })
      end.to raise_error(Ollama::NotFoundError) do |error|
        expect(error.requested_model).to eq("llama")
        # Should find models containing "llama"
        expect(error.suggestions).to include("llama3.1:8b", "llama3.1:7b")
      end
    end

    it "suggests models by partial name match" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "llama3.1:8b" },
              { name: "llama3.2:8b" }
            ]
          }.to_json
        )

      config.model = "llama"

      expect do
        client.generate(prompt: "test", schema: { "type" => "object" })
      end.to raise_error(Ollama::NotFoundError) do |error|
        expect(error.suggestions).to include("llama3.1:8b", "llama3.2:8b")
      end
    end

    it "suggests models by fuzzy matching on parts" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "llama3.1:8b" },
              { name: "qwen2.5:7b" }
            ]
          }.to_json
        )

      config.model = "llama3"

      expect do
        client.generate(prompt: "test", schema: { "type" => "object" })
      end.to raise_error(Ollama::NotFoundError) do |error|
        expect(error.suggestions).to include("llama3.1:8b")
      end
    end

    it "limits suggestions to 5 models" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: (1..10).map { |i| { name: "model#{i}" } }
          }.to_json
        )

      config.model = "model"

      expect do
        client.generate(prompt: "test", schema: { "type" => "object" })
      end.to raise_error(Ollama::NotFoundError) do |error|
        expect(error.suggestions.length).to be <= 5
      end
    end

    it "returns original error if model listing fails" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 404, body: "Not Found")

      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 500, body: "Internal Server Error")

      expect do
        client.generate(prompt: "test", schema: { "type" => "object" })
      end.to raise_error(Ollama::NotFoundError) do |error|
        expect(error.requested_model).to eq("nonexistent-model")
        expect(error.suggestions).to eq([])
      end
    end
  end
end

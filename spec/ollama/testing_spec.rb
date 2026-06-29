# frozen_string_literal: true

require "spec_helper"
require "ollama/testing"

RSpec.describe Ollama::Testing do
  include described_class

  before do
    clear_ollama_stubs
    # Reset config transport adapter
    Ollama.config.transport_adapter = :net_http
  end

  after do
    clear_ollama_stubs
    Ollama.config.transport_adapter = :net_http
  end

  describe "#stub_ollama_chat" do
    it "stubs response" do
      stub_ollama_chat(content: "This is a test response", model: "qwen3.5:4b")

      client = Ollama::Client.new
      response = client.chat(messages: [{ role: "user", content: "hello" }])

      expect(response.content).to eq("This is a test response")
      expect(response.model).to eq("qwen3.5:4b")
    end

    it "stubs Ollama.chat delegated response" do
      stub_ollama_chat(content: "Direct module response", model: "qwen3.5:4b")
      response = Ollama.chat(messages: [{ role: "user", content: "hello" }])
      expect(response.content).to eq("Direct module response")
    end
  end

  describe "#stub_ollama_generate" do
    it "stubs generate response" do
      stub_ollama_generate(content: "This is a generate response", model: "qwen3.5:4b")

      client = Ollama::Client.new
      response = client.generate(prompt: "hello")

      expect(response).to eq("This is a generate response")
    end

    it "stubs Ollama.generate delegated response" do
      stub_ollama_generate(content: "Direct generate response", model: "qwen3.5:4b")
      response = Ollama.generate(prompt: "hello")
      expect(response).to eq("Direct generate response")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Providers::OpenAI do
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:8080/v1"
      c.provider = :openai
    end
  end
  let(:transport) { Ollama::Transport.build(config) }
  let(:provider) { described_class.new(config, transport) }

  describe "#chat_endpoint" do
    it "returns the OpenAI chat completions endpoint" do
      expect(provider.chat_endpoint.to_s).to eq("http://localhost:8080/v1/chat/completions")
    end

    it "handles trailing slash in base_url" do
      config.base_url = "http://localhost:8080/v1/"
      expect(provider.chat_endpoint.to_s).to eq("http://localhost:8080/v1/chat/completions")
    end
  end

  describe "#format_chat_request" do
    it "flattens options and translates format to response_format" do
      params = {
        model: "test-model",
        messages: [{ role: "user", content: "hello" }],
        format: "json",
        options: { temperature: 0.7, num_ctx: 4096 }
      }

      formatted = provider.format_chat_request(params)

      expect(formatted[:model]).to eq("test-model")
      expect(formatted[:temperature]).to eq(0.7)
      expect(formatted[:max_tokens]).to eq(4096)
      expect(formatted[:response_format]).to eq({ type: "json_object" })
      expect(formatted).not_to have_key(:options)
      expect(formatted).not_to have_key(:format)
    end
  end

  describe "#normalize_chat_response" do
    it "translates OpenAI chat response to Ollama format" do
      openai_response = {
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1_677_652_288,
        "model" => "gpt-3.5-turbo",
        "choices" => [{
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => "Hello world"
          },
          "finish_reason" => "stop"
        }],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }

      normalized = provider.normalize_chat_response(openai_response)

      expect(normalized["model"]).to eq("gpt-3.5-turbo")
      expect(normalized["message"]["content"]).to eq("Hello world")
      expect(normalized["message"]["role"]).to eq("assistant")
      expect(normalized["done"]).to be true
      expect(normalized["usage"]["total_tokens"]).to eq(30)
    end
  end

  describe "integration with Ollama::Client" do
    let(:client) { Ollama::Client.new(config: config) }

    it "sends OpenAI format request and returns normalized response" do
      stub_request(:post, "http://localhost:8080/v1/chat/completions")
        .with(body: /"model":"test-model"/)
        .to_return(
          status: 200,
          body: {
            "choices" => [{
              "message" => { "role" => "assistant", "content" => "OpenAI Response" },
              "finish_reason" => "stop"
            }]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      response = client.chat(messages: [{ role: "user", content: "hi" }], model: "test-model")
      expect(response.content).to eq("OpenAI Response")
    end

    it "handles streaming responses" do
      stub_request(:post, "http://localhost:8080/v1/chat/completions")
        .to_return(
          status: 200,
          body: [
            "data: #{{ "choices" => [{ "delta" => { "content" => "Hello" } }] }.to_json}\n",
            "data: #{{ "choices" => [{ "delta" => { "content" => " world" }, "finish_reason" => "stop" }] }.to_json}\n",
            "data: [DONE]\n"
          ].join,
          headers: { "Content-Type" => "text/event-stream" }
        )

      tokens = []
      client.chat(
        messages: [{ role: "user", content: "hi" }],
        model: "test-model",
        hooks: { on_token: ->(t) { tokens << t } }
      )

      expect(tokens).to eq(["Hello", " world"])
    end
  end
end

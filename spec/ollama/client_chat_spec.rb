# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#chat" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
      c.retries = 2
      c.timeout = 5
    end
  end
  let(:messages) do
    [
      { role: "user", content: "Hello" }
    ]
  end
  let(:schema) do
    {
      "type" => "object",
      "required" => ["response"],
      "properties" => {
        "response" => { "type" => "string" }
      }
    }
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "successful requests" do
    it "requires explicit opt-in to use chat()" do
      expect do
        client.chat(messages: messages, format: schema)
      end.to raise_error(Ollama::Error, /gated/i)
    end

    it "returns parsed and validated JSON response" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(
          body: hash_including(
            model: "test-model",
            messages: messages,
            stream: false,
            format: schema
          )
        )
        .to_return(
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: '{"response":"Hello there!"}'
            }
          }.to_json
        )

      result = client.chat(messages: messages, format: schema, allow_chat: true)

      expect(result).to eq("response" => "Hello there!")
    end

    it "allows model override" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/chat")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: '{"response":"test"}'
            }
          }.to_json
        )

      client.chat(messages: messages, model: "custom-model", format: schema, allow_chat: true)

      expect(request_body["model"]).to eq("custom-model")
    end

    it "merges options with config defaults" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/chat")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: '{"response":"test"}'
            }
          }.to_json
        )

      client.chat(
        messages: messages,
        format: schema,
        options: { temperature: 0.5 },
        allow_chat: true
      )

      expect(request_body.dig("options", "temperature")).to eq(0.5)
      expect(request_body.dig("options", "top_p")).to eq(config.top_p)
      expect(request_body.dig("options", "num_ctx")).to eq(config.num_ctx)
    end

    it "works without format parameter" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/chat")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: '"Plain text response"' # JSON string, not plain text
            }
          }.to_json
        )

      result = client.chat(messages: messages, allow_chat: true)

      expect(request_body).not_to have_key("format")
      # Content is a JSON string, so parse_json_response will parse it
      expect(result).to eq("Plain text response")
    end
  end

  describe "error handling" do
    context "when model is not found (404)" do
      it "raises NotFoundError with model suggestions" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(status: 404, body: "Not Found")

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(
            status: 200,
            body: {
              models: [
                { name: "test-model-v2" }
              ]
            }.to_json
          )

        expect do
          client.chat(messages: messages, format: schema, allow_chat: true)
        end.to raise_error(Ollama::NotFoundError) do |error|
          expect(error.requested_model).to eq("test-model")
          expect(error.suggestions).to include("test-model-v2")
        end
      end
    end

    context "when server returns 500 (retryable)" do
      it "retries up to config.retries times" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(status: 500, body: "Internal Server Error")
          .times(config.retries + 1)

        expect do
          client.chat(messages: messages, format: schema, allow_chat: true)
        end.to raise_error(Ollama::RetryExhaustedError)

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat")
          .times(config.retries + 1)
      end
    end

    context "when response violates schema" do
      it "retries on SchemaViolationError" do
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(
            {
              status: 200,
              body: {
                message: {
                  role: "assistant",
                  content: '{"response":123}' # Wrong type
                }
              }.to_json
            },
            {
              status: 200,
              body: {
                message: {
                  role: "assistant",
                  content: '{"response":"correct"}'
                }
              }.to_json
            }
          )

        result = client.chat(messages: messages, format: schema, allow_chat: true)

        expect(result).to eq("response" => "correct")
        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/chat").twice
      end
    end
  end

  describe "multi-turn conversations" do
    it "sends conversation history" do
      request_body = nil
      conversation_messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
        { role: "user", content: "How are you?" }
      ]

      stub_request(:post, "http://localhost:11434/api/chat")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: {
            message: {
              role: "assistant",
              content: '{"response":"I am doing well"}'
            }
          }.to_json
        )

      result = client.chat(messages: conversation_messages, format: schema, allow_chat: true)

      # WebMock stringifies keys, so compare with string keys
      expected_messages = conversation_messages.map { |m| m.transform_keys(&:to_s) }
      expect(request_body["messages"]).to eq(expected_messages)
      expect(result).to eq("response" => "I am doing well")
    end
  end
end

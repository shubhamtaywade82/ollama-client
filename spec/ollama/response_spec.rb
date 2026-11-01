# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Response do
  describe "accessor methods" do
    let(:data) do
      {
        "model" => "qwen2.5-coder:7b",
        "created_at" => "2025-01-01T00:00:00Z",
        "message" => {
          "role" => "assistant",
          "content" => "Hello!",
          "thinking" => "Let me think...",
          "images" => ["base64data"],
          "tool_calls" => [
            {
              "function" => {
                "name" => "get_weather",
                "description" => "Get weather",
                "arguments" => { "city" => "Tokyo" }
              }
            }
          ]
        },
        "done" => true,
        "done_reason" => "stop",
        "total_duration" => 1_000_000,
        "load_duration" => 200_000,
        "prompt_eval_count" => 10,
        "prompt_eval_duration" => 300_000,
        "eval_count" => 20,
        "eval_duration" => 500_000,
        "logprobs" => [{ "token" => "Hello", "logprob" => -0.1 }]
      }
    end
    let(:response) { described_class.new(data) }

    it "exposes all timing fields" do
      expect(response.total_duration).to eq(1_000_000)
      expect(response.load_duration).to eq(200_000)
      expect(response.prompt_eval_count).to eq(10)
      expect(response.prompt_eval_duration).to eq(300_000)
      expect(response.eval_count).to eq(20)
      expect(response.eval_duration).to eq(500_000)
    end

    it "exposes done? and done_reason" do
      expect(response.done?).to be true
      expect(response.done_reason).to eq("stop")
    end

    it "exposes model and created_at" do
      expect(response.model).to eq("qwen2.5-coder:7b")
      expect(response.created_at).to eq("2025-01-01T00:00:00Z")
    end

    it "exposes logprobs" do
      expect(response.logprobs.first["token"]).to eq("Hello")
    end

    it "provides content shorthand" do
      expect(response.content).to eq("Hello!")
    end

    it "exposes message thinking" do
      expect(response.message.thinking).to eq("Let me think...")
    end

    it "exposes message images" do
      expect(response.message.images).to eq(["base64data"])
    end

    it "exposes tool call function description" do
      expect(response.message.tool_calls.first.function.description).to eq("Get weather")
    end
  end

  describe "#parsed and #parsed_content" do
    it "parses plain JSON content" do
      res = described_class.new({ "message" => { "content" => '{"answer": 42}' } })
      expect(res.parsed).to eq({ "answer" => 42 })
      expect(res.parsed_content).to eq({ "answer" => 42 })
    end

    it "extracts JSON wrapped in markdown fences" do
      res = described_class.new({ "message" => { "content" => "```json\n{\"status\":\"ok\"}\n```" } })
      expect(res.parsed).to eq({ "status" => "ok" })
    end

    it "extracts JSON embedded in surrounding prose" do
      res = described_class.new({ "message" => { "content" => 'Here is the data: {"count": 5}. Have fun!' } })
      expect(res.parsed).to eq({ "count" => 5 })
    end

    it "returns nil when content is nil" do
      res = described_class.new({})
      expect(res.parsed).to be_nil
    end

    it "raises InvalidJSONError when content has no valid JSON" do
      res = described_class.new({ "message" => { "content" => "no json here" } })
      expect { res.parsed }.to raise_error(Ollama::InvalidJSONError)
    end
  end
end

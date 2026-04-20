# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client do
  let(:client) { described_class.new }

  describe "#profile" do
    it "returns a ModelProfile for the given model name" do
      p = client.profile("gemma4:31b-cloud")
      expect(p).to be_a(Ollama::ModelProfile)
      expect(p.family).to eq(:gemma4)
      expect(p.thinking?).to be true
    end

    it "returns a generic profile for unknown models" do
      p = client.profile("llama3.2:3b")
      expect(p.family).to eq(:generic)
    end
  end

  describe "#history_sanitizer" do
    it "returns a HistorySanitizer for a model name" do
      s = client.history_sanitizer("gemma4:12b")
      expect(s).to be_a(Ollama::HistorySanitizer)
    end

    it "accepts a ModelProfile directly" do
      profile = Ollama::ModelProfile.for("gemma4:12b")
      s = client.history_sanitizer(profile)
      expect(s).to be_a(Ollama::HistorySanitizer)
    end
  end

  describe "#chat with profile: :auto" do
    let(:model) { "gemma4:12b" }
    let(:base_url) { "http://localhost:11434" }

    let(:response_body) do
      {
        model: model,
        message: { role: "assistant", content: "The answer is 42." },
        done: true,
        done_reason: "stop",
        total_duration: 1_500_000_000,
        prompt_eval_count: 10,
        eval_count: 8
      }.to_json
    end

    before do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "returns a Response and injects <|think|> into system prompt for gemma4 when think: true" do
      response = client.chat(
        model: model,
        think: true,
        messages: [
          { role: "system", content: "You are helpful." },
          { role: "user", content: "What is 6*7?" }
        ]
      )
      expect(response).to be_a(Ollama::Response)
      expect(response.content).to eq("The answer is 42.")

      expect(WebMock).to(have_requested(:post, "#{base_url}/api/chat").with do |req|
        body = JSON.parse(req.body)
        body["messages"][0]["content"].start_with?("<|think|>")
      end)
    end

    it "does not send think: true in body for gemma4 (uses system tag instead)" do
      client.chat(
        model: model,
        think: true,
        messages: [{ role: "user", content: "hello" }]
      )

      expect(WebMock).to(have_requested(:post, "#{base_url}/api/chat").with do |req|
        body = JSON.parse(req.body)
        body["think"].nil?
      end)
    end

    it "applies gemma4 model-aware temperature by default" do
      client.chat(model: model, messages: [{ role: "user", content: "hi" }])

      expect(WebMock).to(have_requested(:post, "#{base_url}/api/chat").with do |req|
        body = JSON.parse(req.body)
        body["options"]["temperature"] == 1.0
      end)
    end

    it "user-supplied options override profile defaults" do
      client.chat(
        model: model,
        options: { temperature: 0.5 },
        messages: [{ role: "user", content: "hi" }]
      )

      expect(WebMock).to(have_requested(:post, "#{base_url}/api/chat").with do |req|
        body = JSON.parse(req.body)
        body["options"]["temperature"] == 0.5
      end)
    end
  end

  describe "#chat with on_thought hook (streaming)" do
    let(:model) { "gemma4:12b" }
    let(:base_url) { "http://localhost:11434" }

    # Each NDJSON chunk must end with \n for the buffer parser
    let(:stream_chunks) do
      [
        { model: model, message: { role: "assistant", content: "", thinking: "Hmm" }, done: false }.to_json,
        { model: model, message: { role: "assistant", content: "42", thinking: "" }, done: false }.to_json,
        { model: model, message: { role: "assistant", content: "", thinking: "" }, done: true,
          done_reason: "stop", total_duration: 1_000_000_000 }.to_json
      ].join("\n") + "\n"
    end

    before do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: stream_chunks, headers: { "Content-Type" => "application/json" })
    end

    it "calls on_thought hook with StreamEvent for reasoning chunks" do
      thought_events = []
      tokens = []

      client.chat(
        model: model,
        messages: [{ role: "user", content: "What is 6*7?" }],
        hooks: {
          on_thought: ->(evt) { thought_events << evt },
          on_token: ->(t) { tokens << t }
        }
      )

      thought_types = thought_events.map(&:type)
      expect(thought_types).to include(:thought_start)
      expect(thought_types).to include(:thought_delta)
      expect(tokens).to include("42")
    end

    it "calls on_complete when streaming finishes" do
      completed = false
      client.chat(
        model: model,
        messages: [{ role: "user", content: "hi" }],
        hooks: { on_complete: -> { completed = true } }
      )
      expect(completed).to be true
    end

    it "emits on_tool_call for tool call chunks" do
      tool_call_data = nil
      chunk_with_tools = {
        model: model,
        message: {
          role: "assistant", content: "", thinking: "",
          tool_calls: [{ function: { name: "get_weather", arguments: { city: "NYC" } } }]
        },
        done: true, done_reason: "stop", total_duration: 500_000_000
      }.to_json + "\n"

      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: chunk_with_tools,
                   headers: { "Content-Type" => "application/json" })

      client.chat(
        model: model,
        messages: [{ role: "user", content: "What's the weather?" }],
        hooks: { on_tool_call: ->(tc) { tool_call_data = tc } }
      )

      expect(tool_call_data).not_to be_nil
      expect(tool_call_data.dig("function", "name")).to eq("get_weather")
    end
  end

  describe "#chat with inputs: multimodal" do
    let(:model) { "gemma4:12b" }
    let(:base_url) { "http://localhost:11434" }

    let(:response_body) do
      { model: model, message: { role: "assistant", content: "I see a chart." },
        done: true }.to_json
    end

    before do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "appends a multimodal message with reordered parts (image before text for gemma4)" do
      client.chat(
        model: model,
        messages: [{ role: "system", content: "You are a vision model." }],
        inputs: [
          { type: :text,  data: "Describe this image." },
          { type: :image, data: "base64imgdata" }
        ]
      )

      expect(WebMock).to(have_requested(:post, "#{base_url}/api/chat").with do |req|
        body = JSON.parse(req.body)
        last_msg = body["messages"].last
        last_msg["images"] == ["base64imgdata"] && last_msg["content"] == "Describe this image."
      end)
    end
  end

  describe "Response#usage and #latency_ms" do
    subject(:response) { Ollama::Response.new(data) }

    let(:data) do
      {
        "model" => "gemma4:12b",
        "message" => { "role" => "assistant", "content" => "hi" },
        "done" => true,
        "total_duration" => 1_500_000_000,
        "prompt_eval_count" => 10,
        "eval_count" => 20
      }
    end

    it "returns usage hash" do
      expect(response.usage).to eq(
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      )
    end

    it "returns latency_ms in milliseconds" do
      expect(response.latency_ms).to eq(1500.0)
    end

    it "returns nil latency when total_duration is absent" do
      r = Ollama::Response.new({})
      expect(r.latency_ms).to be_nil
    end
  end
end

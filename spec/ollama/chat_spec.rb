# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Ollama::Chat do
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "qwen3.5:4b"
      c.retries = 2
    end
  end
  let(:client) { Ollama::Client.new(config: config) }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "initialization via client.chat" do
    it "returns an Ollama::Chat instance when messages is omitted" do
      chat = client.chat(model: "qwen3.5:4b")
      expect(chat).to be_a(described_class)
      expect(chat.model).to eq("qwen3.5:4b")
      expect(chat.messages).to be_empty
    end

    it "initializes with system prompt when given" do
      chat = described_class.new(client, system: "Act as an expert")
      expect(chat.messages).to eq([{ role: "system", content: "Act as an expert" }])
    end
  end

  describe "#ask multi-turn conversation" do
    it "retains history automatically across turns" do
      chat = client.chat(model: "qwen3.5:4b")

      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("messages" => [{ "role" => "user", "content" => "Hello" }]))
        .to_return(status: 200, body: { message: { role: "assistant", content: "Hi there!" }, done: true }.to_json)

      res1 = chat.ask("Hello")
      expect(res1.content).to eq("Hi there!")
      expect(chat.messages.length).to eq(2)

      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("messages" => [
                                     { "role" => "user", "content" => "Hello" },
                                     { "role" => "assistant", "content" => "Hi there!" },
                                     { "role" => "user", "content" => "How are you?" }
                                   ]))
        .to_return(status: 200, body: { message: { role: "assistant", content: "I am great!" }, done: true }.to_json)

      res2 = chat.ask("How are you?")
      expect(res2.content).to eq("I am great!")
      expect(chat.messages.length).to eq(4)
    end

    it "records tool calls returned in assistant response" do
      chat = client.chat(model: "qwen3.5:4b")
      tool_call = { "function" => { "name" => "weather", "arguments" => { "city" => "Paris" } } }

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "", tool_calls: [tool_call] }, done: true
        }.to_json)

      chat.ask("What is the weather?")
      expect(chat.messages.last[:tool_calls]).to eq([tool_call])
    end
  end

  describe "streaming with block" do
    it "yields tokens to block and records complete response in history" do
      chat = client.chat(model: "qwen3.5:4b")
      tokens = []

      lines = [
        { message: { role: "assistant", content: "Hel" }, done: false }.to_json,
        { message: { role: "assistant", content: "lo" }, done: true }.to_json
      ]
      ndjson = "#{lines.join("\n")}\n"

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: ndjson)

      chat.ask("Say hello") { |chunk| tokens << chunk }

      expect(tokens).to eq(%w[Hel lo])
      expect(chat.messages.last[:content]).to eq("Hello")
    end
  end

  describe "HistorySanitizer integration" do
    it "excludes thinking content from conversation history" do
      chat = client.chat(model: "gemma4:12b")

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "42", thinking: "Pondering the universe..." },
          done: true
        }.to_json)

      chat.ask("What is the answer?")
      expect(chat.messages.last).to eq({ role: "assistant", content: "42" })
    end

    it "records traces when trace_store is provided" do
      traces = []
      chat = described_class.new(client, model: "gemma4:12b", trace_store: traces)

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: {
          model: "gemma4:12b",
          message: { role: "assistant", content: "Paris", thinking: "Capital search" },
          done: true
        }.to_json)

      chat.ask("France capital?")
      expect(traces.length).to eq(1)
      expect(traces.first[:thinking]).to eq("Capital search")
      expect(traces.first[:final]).to eq("Paris")
    end
  end

  describe "fluent configuration and reset" do
    let(:chat) { client.chat }

    it "sets instructions and appends when append: true" do
      chat.with_instructions("Rule 1")
      expect(chat.messages.first[:content]).to eq("Rule 1")

      chat.with_instructions("Rule 2", append: true)
      expect(chat.messages.first[:content]).to eq("Rule 1\n\nRule 2")
    end

    it "sets model, temperature, think, keep_alive, tools, and format" do
      chat.with_model("qwen2.5:0.5b")
          .with_temperature(0.5)
          .with_think(true)
          .with_keep_alive("15m")
          .with_tools([{ name: "test_tool" }])
          .with_schema({ "type" => "object" })

      expect(chat.model).to eq("qwen2.5:0.5b")
      expect(chat.options[:temperature]).to eq(0.5)
      expect(chat.think).to be true
      expect(chat.keep_alive).to eq("15m")
      expect(chat.tools).to eq([{ name: "test_tool" }])
      expect(chat.format).to eq({ "type" => "object" })
    end

    it "reset! clears history but preserves instructions" do
      chat.with_instructions("System prompt")
      chat.add_message(role: "user", content: "Hi")
      chat.add_message(role: "assistant", content: "Hey")

      chat.reset!
      expect(chat.messages).to eq([{ role: "system", content: "System prompt" }])
    end
  end

  describe "validation & repair loop on chat(format:)" do
    let(:schema) do
      {
        "type" => "object",
        "required" => ["answer"],
        "properties" => { "answer" => { "type" => "string" } }
      }
    end

    it "auto-repairs schema violations in Chat#ask" do
      chat = client.chat(model: "qwen3.5:4b").with_schema(schema)

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(
          { status: 200, body: { message: { role: "assistant", content: '{"wrong_key":"Paris"}' }, done: true }.to_json },
          { status: 200, body: { message: { role: "assistant", content: '{"answer":"Paris"}' }, done: true }.to_json }
        )

      response = chat.ask("Capital?")
      expect(response.parsed).to eq({ "answer" => "Paris" })
      expect(a_request(:post, "http://localhost:11434/api/chat")).to have_been_made.twice
      expect(a_request(:post, "http://localhost:11434/api/chat").with { |r| r.body.include?("CRITICAL FIX") }).to have_been_made.once
    end

    it "client.chat with strict: true validates and auto-repairs" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(
          { status: 200, body: { message: { role: "assistant", content: "not valid json at all" }, done: true }.to_json },
          { status: 200, body: { message: { role: "assistant", content: '{"answer":"Paris"}' }, done: true }.to_json }
        )

      response = client.chat(
        messages: [{ role: "user", content: "Capital?" }],
        format: schema,
        strict: true
      )
      expect(response.parsed).to eq({ "answer" => "Paris" })
      expect(a_request(:post, "http://localhost:11434/api/chat")).to have_been_made.twice
      expect(a_request(:post, "http://localhost:11434/api/chat").with { |r| r.body.include?("CRITICAL FIX") }).to have_been_made.once
    end

    it "raises SchemaViolationError when retries are exhausted" do
      chat = client.chat.with_schema(schema)

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: {
          message: { role: "assistant", content: '{"wrong":"bad"}' }, done: true
        }.to_json)

      expect { chat.ask("Capital?") }.to raise_error(Ollama::SchemaViolationError)
    end
  end
end

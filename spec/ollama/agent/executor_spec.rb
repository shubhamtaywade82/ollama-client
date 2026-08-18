# frozen_string_literal: true

require "spec_helper"
require "ollama/agent/executor"
require "ollama/streaming_observer"
require "ollama/tool"

# Regression coverage for #tool_definitions: a stray, copy-pasted fragment
# from #infer_parameters (schema = {...}; schema["properties"] = properties
# ...) used to sit after this method's real `.map` block, referencing
# undefined local variables `properties`/`required` — so calling it always
# raised NameError instead of returning the built tool definitions array.
RSpec.describe Ollama::Agent::Executor do
  let(:client) { Ollama::Client.new }

  describe "#tool_definitions (private)" do
    it "returns the OpenAI-style tool array for an explicit Ollama::Tool" do
      tool = Ollama::Tool.new(
        type: "function",
        function: Ollama::Tool::Function.new(
          name: "get_weather",
          description: "Get the weather",
          parameters: Ollama::Tool::Function::Parameters.new(type: "object", properties: {}, required: [])
        )
      )
      executor = described_class.new(client, tools: { get_weather: tool })

      definitions = executor.send(:tool_definitions)

      expect(definitions).to eq([tool.to_h])
    end

    it "infers a schema for a plain callable" do
      greeter = ->(name:) { "hi #{name}" }
      executor = described_class.new(client, tools: { greet: greeter })

      definitions = executor.send(:tool_definitions)

      expect(definitions.size).to eq(1)
      expect(definitions.first[:function][:name]).to eq("greet")
      expect(definitions.first[:function][:parameters]).to include("required" => ["name"])
    end

    it "returns an empty array when there are no tools" do
      executor = described_class.new(client, tools: {})

      expect(executor.send(:tool_definitions)).to eq([])
    end
  end

  describe "#run" do
    let(:executor) do
      described_class.new(client, tools: { get_weather: ->(city:) { "sunny in #{city}" } })
    end

    it "executes tool calls in a loop and returns the final content" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(
          { status: 200, body: {
            message: {
              role: "assistant",
              content: "",
              tool_calls: [
                { id: "call_1", function: { name: "get_weather", arguments: { city: "London" } } }
              ]
            },
            done: true
          }.to_json },
          { status: 200, body: {
            message: { role: "assistant", content: "Sunny in London" },
            done: true
          }.to_json }
        )

      result = executor.run(system: "You are helpful", user: "Weather in London?")

      expect(result).to eq("Sunny in London")
      expect(executor.messages.map { |m| m[:role] })
        .to eq(%w[system user assistant tool assistant])
      expect(executor.messages[2][:tool_calls].first["function"]["name"]).to eq("get_weather")
      expect(executor.messages[3]).to eq(
        { role: "tool", content: "sunny in London", name: "get_weather", tool_call_id: "call_1" }
      )
    end

    it "raises when the model requests an unknown tool" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "", tool_calls: [
            { id: "call_1", function: { name: "nope", arguments: {} } }
          ] },
          done: true
        }.to_json)

      expect do
        executor.run(system: "s", user: "u")
      end.to raise_error(Ollama::Error, /Tool 'nope' not found/)
    end

    it "emits stream events when given an observer" do
      events = []
      observer = Ollama::StreamingObserver.new { |e| events << e }

      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: "#{[
          { message: { role: "assistant", content: "Do" }, done: false }.to_json,
          { message: { role: "assistant", content: "ne" }, done: false }.to_json,
          { message: { role: "assistant", content: "" }, done: true }.to_json
        ].join("\n")}\n")

      streaming_executor = described_class.new(
        client, tools: {}, stream: observer
      )
      result = streaming_executor.run(system: "s", user: "u")

      expect(result).to eq("Done")
      expect(events.map(&:type)).to include(:token, :final)
    end
  end
end

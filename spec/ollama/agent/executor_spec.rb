# frozen_string_literal: true

require "spec_helper"
require "ollama/agent/executor"
require "ollama/tool"

# Regression coverage for #tool_definitions: a stray, copy-pasted fragment
# from #infer_parameters (schema = {...}; schema["properties"] = properties
# ...) used to sit after this method's real `.map` block, referencing
# undefined local variables `properties`/`required` — so calling it always
# raised NameError instead of returning the built tool definitions array.
#
# #run itself is not covered here — see the NOTE in
# lib/ollama/agent/executor.rb: it calls a Client method (chat_raw) that no
# longer exists, a separate, larger, currently-undecided issue.
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
      expect(definitions.first[:function][:name]).to eq(:greet)
      expect(definitions.first[:function][:parameters]).to include("required" => ["name"])
    end

    it "returns an empty array when there are no tools" do
      executor = described_class.new(client, tools: {})

      expect(executor.send(:tool_definitions)).to eq([])
    end
  end
end

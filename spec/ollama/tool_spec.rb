# frozen_string_literal: true

require "spec_helper"

# Regression coverage for lib/ollama/tool.rb and its Function/Parameters/
# Property DTOs: this whole family was never required by lib/ollama_client.rb
# (fixed to require "ollama/tool"), so every example script that used
# Ollama::Tool directly (examples/tool_calling_direct.rb,
# examples/tool_dto_example.rb, examples/structured_tools.rb) raised
# NameError before it ever reached real behavior.
RSpec.describe Ollama::Tool do
  let(:property) do
    Ollama::Tool::Function::Parameters::Property.new(
      type: "string",
      description: "City name",
      enum: %w[paris london]
    )
  end
  let(:parameters) do
    Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: { city: property },
      required: ["city"]
    )
  end
  let(:function) do
    Ollama::Tool::Function.new(name: "get_weather", description: "Get weather", parameters: parameters)
  end
  let(:tool) { described_class.new(type: "function", function: function) }

  it "is a real constant once ollama_client is loaded (no extra require needed)" do
    expect(Ollama::Client.new).to respond_to(:chat)
    expect(described_class).to be_a(Class)
  end

  it "serializes to the OpenAI-style function-tool hash shape" do
    expect(tool.to_h).to eq(
      type: "function",
      function: {
        name: "get_weather",
        description: "Get weather",
        parameters: {
          "type" => "object",
          "properties" => { city: { "type" => "string", "description" => "City name", "enum" => %w[paris london] } },
          "required" => ["city"]
        }
      }
    )
  end

  it "round-trips through to_h -> from_hash" do
    rebuilt = described_class.from_hash(tool.to_h)

    expect(rebuilt.type).to eq(tool.type)
    expect(rebuilt.function.name).to eq(tool.function.name)
    expect(rebuilt.to_h).to eq(tool.to_h)
  end

  it "serializes cleanly to JSON (as used when passed in tools:)" do
    expect { tool.to_json }.not_to raise_error
    expect(JSON.parse(tool.to_json)).to eq(JSON.parse(tool.to_h.to_json))
  end
end

# frozen_string_literal: true

require "json"

RSpec.describe Ollama::Tool do
  describe "#initialize" do
    it "creates tool with type and function" do
      function = Ollama::Tool::Function.new(
        name: "test",
        description: "Test function"
      )
      tool = described_class.new(type: "function", function: function)

      expect(tool.type).to eq("function")
      expect(tool.function).to eq(function)
    end

    it "converts type to string" do
      function = Ollama::Tool::Function.new(name: "test", description: "Test")
      tool = described_class.new(type: :function, function: function)

      expect(tool.type).to eq("function")
    end
  end

  describe ".from_hash" do
    it "creates tool from hash" do
      hash = {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get weather"
        }
      }

      tool = described_class.from_hash(hash)

      expect(tool.type).to eq("function")
      expect(tool.function.name).to eq("get_weather")
    end

    it "handles string keys" do
      hash = {
        "type" => "function",
        "function" => {
          "name" => "test",
          "description" => "Test"
        }
      }

      tool = described_class.from_hash(hash)

      expect(tool.type).to eq("function")
      expect(tool.function.name).to eq("test")
    end
  end

  describe "#to_h" do
    it "converts tool to hash" do
      function = Ollama::Tool::Function.new(
        name: "test",
        description: "Test function"
      )
      tool = described_class.new(type: "function", function: function)

      hash = tool.to_h

      expect(hash[:type]).to eq("function")
      expect(hash[:function]).to be_a(Hash)
      expect(hash[:function][:name]).to eq("test")
    end
  end

  describe "#to_json" do
    it "serializes tool to JSON" do
      function = Ollama::Tool::Function.new(
        name: "test",
        description: "Test function"
      )
      tool = described_class.new(type: "function", function: function)

      json = tool.to_json
      parsed = JSON.parse(json)

      expect(parsed["type"]).to eq("function")
      expect(parsed["function"]["name"]).to eq("test")
    end
  end

  describe "#==" do
    it "compares tools by hash representation" do
      function1 = Ollama::Tool::Function.new(name: "test", description: "Test")
      function2 = Ollama::Tool::Function.new(name: "test", description: "Test")
      tool1 = described_class.new(type: "function", function: function1)
      tool2 = described_class.new(type: "function", function: function2)

      expect(tool1).to eq(tool2)
    end

    it "returns false for different tools" do
      function1 = Ollama::Tool::Function.new(name: "test1", description: "Test")
      function2 = Ollama::Tool::Function.new(name: "test2", description: "Test")
      tool1 = described_class.new(type: "function", function: function1)
      tool2 = described_class.new(type: "function", function: function2)

      expect(tool1).not_to eq(tool2)
    end
  end
end

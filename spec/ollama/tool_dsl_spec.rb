# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::ToolDSL do
  describe ".to_tool_hash" do
    it "produces chat-compatible tool definition" do
      klass = Class.new(described_class) do
        description "Get weather"
        input { string :city }
        call { {} }
      end

      result = klass.to_tool_hash
      expect(result["type"]).to eq("function")
      expect(result.dig("function", "name")).to eq("get_weather")
      expect(result.dig("function", "description")).to eq("Get weather")
      expect(result.dig("function", "strict")).to be(true)
      expect(result.dig("function", "parameters")).to have_key("type")
      expect(result.dig("function", "parameters", "required")).to include("city")
    end

    it "normalizes camelized names to snake_case" do
      klass = Class.new(described_class) do
        description "My tool"
        input { string :dummy }
        call { "result" }
      end

      expect(klass.to_tool_hash.dig("function", "name")).to eq("my_tool")
    end
  end
end

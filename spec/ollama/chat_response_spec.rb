# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::ChatResponse do
  describe "#initialize" do
    it "defaults role to assistant" do
      expect(described_class.new.role).to eq("assistant")
    end

    it "defaults done to true" do
      expect(described_class.new).to be_done
    end

    it "defaults tool_calls and images as empty arrays" do
      response = described_class.new
      expect(response.tool_calls).to eq([])
      expect(response.images).to eq([])
    end
  end

  describe "#done?" do
    it "returns true when done is true" do
      expect(described_class.new(done: true)).to be_done
    end

    it "returns false when done is false" do
      expect(described_class.new(done: false)).not_to be_done
    end
  end

  describe "attribute storage" do
    it "stores content, thinking, and model" do
      response = described_class.new(content: "hi", thinking: "t", model: "m")
      expect(response.content).to eq("hi")
      expect(response.thinking).to eq("t")
      expect(response.model).to eq("m")
    end

    it "coerces standalone tool_calls and images arguments to arrays" do
      t = described_class.new(tool_calls: [{ name: "t" }], images: ["i"])
      expect(t.tool_calls).to eq([{ name: "t" }])
      expect(t.images).to eq(["i"])
    end

    it "preserves role value" do
      expect(described_class.new(role: "user").role).to eq("user")
    end
  end
end

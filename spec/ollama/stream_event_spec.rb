# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::StreamEvent do
  describe "type predicates" do
    it "identifies thought events" do
      expect(described_class.new(type: :thought_delta, data: "hello").thought?).to be true
      expect(described_class.new(type: :thought_start, data: nil).thought?).to be true
      expect(described_class.new(type: :thought_end, data: nil).thought?).to be true
    end

    it "identifies answer events" do
      expect(described_class.new(type: :answer_delta, data: "hi").answer?).to be true
      expect(described_class.new(type: :thought_delta, data: "x").answer?).to be false
    end

    it "identifies tool_call events" do
      expect(described_class.new(type: :tool_call_start, data: {}).tool_call?).to be true
      expect(described_class.new(type: :tool_call_delta, data: {}).tool_call?).to be true
    end

    it "identifies terminal events" do
      expect(described_class.new(type: :complete, data: nil).terminal?).to be true
      expect(described_class.new(type: :error, data: nil).terminal?).to be true
      expect(described_class.new(type: :answer_delta, data: "x").terminal?).to be false
    end
  end

  describe "#to_jsonl" do
    it "returns a JSON string" do
      event = described_class.new(type: :thought_delta, data: "thinking...", model: "gemma4")
      json = event.to_jsonl
      parsed = JSON.parse(json)
      expect(parsed["type"]).to eq("thought_delta")
      expect(parsed["data"]).to eq("thinking...")
      expect(parsed["model"]).to eq("gemma4")
    end
  end
end

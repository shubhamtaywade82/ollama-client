# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::HistorySanitizer do
  let(:gemma4_profile) { Ollama::ModelProfile.for("gemma4:12b") }
  let(:generic_profile) { Ollama::ModelProfile.for("llama3.2:3b") }

  def make_response(content:, thinking: nil, model: "gemma4:12b")
    data = {
      "model"   => model,
      "message" => { "role" => "assistant", "content" => content, "thinking" => thinking }.compact,
      "done"    => true
    }
    Ollama::Response.new(data)
  end

  describe ".for" do
    it "creates :exclude_thoughts sanitizer for reasoning models" do
      s = described_class.for(gemma4_profile)
      expect(s).to be_a(described_class)
    end

    it "creates :none sanitizer for generic models" do
      s = described_class.for(generic_profile)
      expect(s).to be_a(described_class)
    end
  end

  describe "#add with :exclude_thoughts policy" do
    subject(:sanitizer) { described_class.for(gemma4_profile) }

    it "appends only final content, not thinking" do
      messages = []
      response = make_response(content: "The answer is 42.", thinking: "Let me think...")
      sanitizer.add(response, messages: messages)
      expect(messages.length).to eq(1)
      expect(messages[0]).to eq({ role: "assistant", content: "The answer is 42." })
    end

    it "stores thought in trace_store when provided" do
      traces = []
      s = described_class.new(policy: :exclude_thoughts, trace_store: traces)
      response = make_response(content: "42", thinking: "deep thought")
      s.add(response, messages: [])
      expect(traces.length).to eq(1)
      expect(traces[0][:thinking]).to eq("deep thought")
      expect(traces[0][:final]).to eq("42")
    end

    it "does not push to trace_store when thinking is empty" do
      traces = []
      s = described_class.new(policy: :exclude_thoughts, trace_store: traces)
      response = make_response(content: "42")
      s.add(response, messages: [])
      expect(traces).to be_empty
    end
  end

  describe "#add with :none policy" do
    subject(:sanitizer) { described_class.for(generic_profile) }

    it "appends content to messages" do
      messages = []
      response = make_response(content: "hello", model: "llama3.2:3b")
      sanitizer.add(response, messages: messages)
      expect(messages[0][:content]).to eq("hello")
    end
  end
end

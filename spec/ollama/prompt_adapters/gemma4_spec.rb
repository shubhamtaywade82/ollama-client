# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::PromptAdapters::Gemma4 do
  subject(:adapter) { described_class.new(profile) }

  let(:profile) { Ollama::ModelProfile.for("gemma4:12b") }

  describe "#inject_think_flag?" do
    it { expect(adapter.inject_think_flag?).to be false }
  end

  describe "#adapt_messages" do
    context "when think is false" do
      it "returns messages unchanged" do
        msgs = [{ role: "user", content: "hello" }]
        expect(adapter.adapt_messages(msgs, think: false)).to eq(msgs)
      end
    end

    context "when think is true with existing system message (symbol keys)" do
      let(:messages) do
        [
          { role: "system", content: "You are helpful." },
          { role: "user", content: "hello" }
        ]
      end

      it "prepends <|think|> to the system message content" do
        result = adapter.adapt_messages(messages, think: true)
        expect(result[0][:content]).to eq("<|think|>You are helpful.")
        expect(result[1]).to eq({ role: "user", content: "hello" })
      end

      it "does not mutate the original messages" do
        adapter.adapt_messages(messages, think: true)
        expect(messages[0][:content]).to eq("You are helpful.")
      end
    end

    context "when think is true with existing system message (string keys)" do
      let(:messages) do
        [
          { "role" => "system", "content" => "You are an expert." },
          { "role" => "user", "content" => "hello" }
        ]
      end

      it "prepends <|think|> to string-keyed system message" do
        result = adapter.adapt_messages(messages, think: true)
        expect(result[0]["content"]).to eq("<|think|>You are an expert.")
      end
    end

    context "when think is true with no system message" do
      let(:messages) { [{ role: "user", content: "hello" }] }

      it "prepends a bare system message with the think tag" do
        result = adapter.adapt_messages(messages, think: true)
        expect(result.length).to eq(2)
        expect(result[0]).to eq({ role: "system", content: "<|think|>" })
        expect(result[1]).to eq({ role: "user", content: "hello" })
      end
    end

    context "when think tag is already present" do
      let(:messages) do
        [{ role: "system", content: "<|think|>Already tagged." }]
      end

      it "does not double-inject the tag" do
        result = adapter.adapt_messages(messages, think: true)
        expect(result[0][:content]).to eq("<|think|>Already tagged.")
      end
    end
  end
end

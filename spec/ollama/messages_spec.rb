# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Messages do
  describe ".new" do
    it "copies base hashes" do
      base = [{ "role" => "user", "content" => "hi" }]
      expect(described_class.new(base).to_h).to eq(base)
    end
  end

  describe "#system" do
    it "replaces existing system message" do
      messages = described_class.new([{ "role" => "user", "content" => "hi" }, { "role" => "system", "content" => "old" }])
      messages.system("new")
      result = messages.to_h
      expect(result.select { |m| m["role"] == "system" }.size).to eq(1)
      expect(result[1]["content"]).to eq("new")
    end

    it "appends when no system message exists" do
      messages = described_class.new([{ "role" => "user", "content" => "hi" }])
      messages.system("new")
      last = messages.to_h.last
      expect(last["role"]).to eq("system")
      expect(last["content"]).to eq("new")
    end

    it "removes system message when content is nil" do
      messages = described_class.new([{ "role" => "system", "content" => "bye" }])
      messages.system(nil)
      expect(messages.to_h).to be_empty
    end
  end

  describe "#user" do
    it "appends user message" do
      messages = described_class.new
      messages.user("hi")
      expect(messages.to_h).to eq([{ "role" => "user", "content" => "hi" }])
    end

    it "attaches images when provided" do
      messages = described_class.new
      messages.user("hi", attachment: Ollama::Attachment.file("photo.png"))
      msg = messages.to_h.first
      expect(msg["images"]).to be_an(Array)
      expect(msg["images"].first).to have_key("type")
    end
  end

  describe "#image" do
    it "adds user message with images" do
      messages = described_class.new
      messages.image("caption", attachment: Ollama::Attachment.base64("abc123"))
      msg = messages.to_h.first
      expect(msg["role"]).to eq("user")
      expect(msg["images"]).to eq([{ "type" => "base64", "data" => "abc123" }])
    end
  end

  describe "#to_h" do
    it "returns a duplicate that can be mutated independently" do
      messages = described_class.new([{ "role" => "user", "content" => "x" }])
      result = messages.to_h
      result << { "role" => "assistant", "content" => "y" }
      expect(messages.size).to eq(1)
    end
  end

  describe "#size" do
    it "counts messages" do
      messages = described_class.new([{ "role" => "user", "content" => "hi" }])
      expect(messages.size).to eq(1)
    end
  end
end

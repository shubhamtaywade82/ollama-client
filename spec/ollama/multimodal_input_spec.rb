# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::MultimodalInput do
  let(:gemma4_profile) { Ollama::ModelProfile.for("gemma4:12b") }
  let(:deepseek_profile) { Ollama::ModelProfile.for("deepseek-r1:7b") }

  describe ".build" do
    it "creates an instance with the given parts" do
      obj = described_class.build(
        [{ type: :text, data: "hello" }],
        profile: gemma4_profile
      )
      expect(obj.parts.length).to eq(1)
      expect(obj.parts[0][:type]).to eq(:text)
    end

    it "reorders parts per profile modality_order (image before text for gemma4)" do
      obj = described_class.build(
        [
          { type: :text, data: "Describe this." },
          { type: :image, data: "base64imgdata" }
        ],
        profile: gemma4_profile
      )
      expect(obj.parts[0][:type]).to eq(:image)
      expect(obj.parts[1][:type]).to eq(:text)
    end
  end

  describe "#add" do
    it "raises ArgumentError for unknown type" do
      obj = described_class.new
      expect do
        obj.add({ type: :video, data: "x" })
      end.to raise_error(ArgumentError, /Unsupported input type/)
    end

    it "raises UnsupportedCapabilityError for image on deepseek" do
      obj = described_class.new
      expect do
        obj.add({ type: :image, data: "x" }, profile: deepseek_profile)
      end.to raise_error(Ollama::UnsupportedCapabilityError)
    end

    it "accepts image on gemma4" do
      obj = described_class.new
      expect { obj.add({ type: :image, data: "imgdata" }, profile: gemma4_profile) }.not_to raise_error
    end
  end

  describe "#to_message" do
    it "builds a user message hash with content and images" do
      obj = described_class.build(
        [
          { type: :image, data: "imgdata" },
          { type: :text, data: "What is this?" }
        ],
        profile: gemma4_profile
      )
      msg = obj.to_message
      expect(msg[:role]).to eq("user")
      expect(msg[:content]).to eq("What is this?")
      expect(msg[:images]).to eq(["imgdata"])
    end

    it "omits :images key when no images present" do
      obj = described_class.build(
        [{ type: :text, data: "hello" }],
        profile: gemma4_profile
      )
      expect(obj.to_message).not_to have_key(:images)
    end

    it "joins multiple text parts with newlines" do
      obj = described_class.new
      obj.add({ type: :text, data: "Part one." })
      obj.add({ type: :text, data: "Part two." })
      expect(obj.to_message[:content]).to eq("Part one.\nPart two.")
    end
  end
end

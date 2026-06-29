# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::ModelProfile do
  describe ".for" do
    context "with gemma4 model" do
      subject(:p) { described_class.for("gemma4:31b-cloud") }

      it "has correct attributes" do
        expect(p.family).to eq(:gemma4)
        expect(p.thinking?).to be true
        expect(p.multimodal?).to be true
        expect(p.tool_calling?).to be true
        expect(p.stream_reasoning?).to be true
        expect(p.history_policy).to eq(:exclude_thoughts)
        expect(p.think_trigger).to eq(:system_prompt_tag)
        expect(p.think_tag).to eq("<|think|>")
        expect(p.default_options[:temperature]).to eq(1.0)
        expect(p.default_options[:top_p]).to eq(0.95)
        expect(p.default_options[:top_k]).to eq(64)
        expect(p.modality_order).to eq(%i[image audio text])
        expect(p.context_window).to eq(128_000)
      end
    end

    context "with gemma4 variant names" do
      it "matches gemma4:12b and gemma-4:12b" do
        expect(described_class.for("gemma4:12b").family).to eq(:gemma4)
        expect(described_class.for("gemma-4:12b").family).to eq(:gemma4)
      end
    end

    context "with deepseek model" do
      subject(:p) { described_class.for("deepseek-r1:7b") }

      it "has correct attributes" do
        expect(p.family).to eq(:deepseek)
        expect(p.thinking?).to be true
        expect(p.multimodal?).to be false
        expect(p.tool_calling?).to be false
        expect(p.history_policy).to eq(:exclude_thoughts)
        expect(p.default_options[:temperature]).to eq(0.6)
      end
    end

    context "with qwen model" do
      subject(:p) { described_class.for("qwen3:14b") }

      it "has correct attributes" do
        expect(p.family).to eq(:qwen)
        expect(p.thinking?).to be true
        expect(p.multimodal?).to be true
        expect(p.tool_calling?).to be true
        expect(p.history_policy).to eq(:exclude_thoughts)
        expect(p.modality_order).to eq(%i[image text])
      end
    end

    context "with embedding model" do
      subject(:p) { described_class.for("nomic-embed-text:latest") }

      it "has correct attributes" do
        expect(p.family).to eq(:embedding)
        expect(p.thinking?).to be false
        expect(p.tool_calling?).to be false
        expect(p.structured_output?).to be false
        expect(p.history_policy).to eq(:none)
      end
    end

    context "with mxbai-embed" do
      it "has embedding family" do
        expect(described_class.for("mxbai-embed-large").family).to eq(:embedding)
      end
    end

    context "with generic / unknown model" do
      subject(:p) { described_class.for("qwen3.5:4b") }

      it "has correct attributes" do
        expect(p.family).to eq(:generic)
        expect(p.thinking?).to be false
        expect(p.tool_calling?).to be true
        expect(p.history_policy).to eq(:none)
        expect(p.default_options[:temperature]).to eq(0.2)
      end
    end
  end

  describe "#supports_modality?" do
    it "returns true for image on gemma4" do
      expect(described_class.for("gemma4:12b").supports_modality?(:image)).to be true
    end

    it "returns false for image on deepseek" do
      expect(described_class.for("deepseek-r1:7b").supports_modality?(:image)).to be false
    end

    it "returns true for text on all families" do
      %w[gemma4:12b deepseek-r1:7b qwen3:4b qwen3.5:4b].each do |m|
        expect(described_class.for(m).supports_modality?(:text)).to be true
      end
    end
  end

  describe "#default_options" do
    it "returns only defined keys (no nils)" do
      profile = described_class.for("gemma4:12b")
      expect(profile.default_options.values).to all(satisfy { |v| !v.nil? })
    end

    it "returns empty hash for models without explicit defaults" do
      profile = described_class.for("qwen3.5:4b")
      expect(profile.default_options).to be_a(Hash)
    end
  end

  describe "#to_h" do
    it "includes model and family keys" do
      profile = described_class.for("gemma4:12b")
      h = profile.to_h
      expect(h[:model]).to eq("gemma4:12b")
      expect(h[:family]).to eq(:gemma4)
    end
  end

  describe "#inspect" do
    it "includes model name and key booleans" do
      profile = described_class.for("gemma4:12b")
      expect(profile.inspect).to include("gemma4:12b")
      expect(profile.inspect).to include("thinking=true")
    end
  end
end

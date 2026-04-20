# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::ModelProfile do
  describe ".for" do
    context "with gemma4 model" do
      subject(:p) { described_class.for("gemma4:31b-cloud") }

      it { expect(p.family).to eq(:gemma4) }
      it { expect(p.thinking?).to be true }
      it { expect(p.multimodal?).to be true }
      it { expect(p.tool_calling?).to be true }
      it { expect(p.stream_reasoning?).to be true }
      it { expect(p.history_policy).to eq(:exclude_thoughts) }
      it { expect(p.think_trigger).to eq(:system_prompt_tag) }
      it { expect(p.think_tag).to eq("<|think|>") }
      it { expect(p.default_options[:temperature]).to eq(1.0) }
      it { expect(p.default_options[:top_p]).to eq(0.95) }
      it { expect(p.default_options[:top_k]).to eq(64) }
      it { expect(p.modality_order).to eq(%i[image audio text]) }
      it { expect(p.context_window).to eq(128_000) }
    end

    context "with gemma4 variant names" do
      it "matches gemma4:12b" do
        expect(described_class.for("gemma4:12b").family).to eq(:gemma4)
      end

      it "matches gemma-4:12b" do
        expect(described_class.for("gemma-4:12b").family).to eq(:gemma4)
      end
    end

    context "with deepseek model" do
      subject(:p) { described_class.for("deepseek-r1:7b") }

      it { expect(p.family).to eq(:deepseek) }
      it { expect(p.thinking?).to be true }
      it { expect(p.multimodal?).to be false }
      it { expect(p.tool_calling?).to be false }
      it { expect(p.history_policy).to eq(:exclude_thoughts) }
      it { expect(p.default_options[:temperature]).to eq(0.6) }
    end

    context "with qwen model" do
      subject(:p) { described_class.for("qwen3:14b") }

      it { expect(p.family).to eq(:qwen) }
      it { expect(p.thinking?).to be true }
      it { expect(p.multimodal?).to be true }
      it { expect(p.tool_calling?).to be true }
      it { expect(p.history_policy).to eq(:exclude_thoughts) }
      it { expect(p.modality_order).to eq(%i[image text]) }
    end

    context "with embedding model" do
      subject(:p) { described_class.for("nomic-embed-text:latest") }

      it { expect(p.family).to eq(:embedding) }
      it { expect(p.thinking?).to be false }
      it { expect(p.tool_calling?).to be false }
      it { expect(p.structured_output?).to be false }
      it { expect(p.history_policy).to eq(:none) }
    end

    context "with mxbai-embed" do
      it { expect(described_class.for("mxbai-embed-large").family).to eq(:embedding) }
    end

    context "with generic / unknown model" do
      subject(:p) { described_class.for("llama3.2:3b") }

      it { expect(p.family).to eq(:generic) }
      it { expect(p.thinking?).to be false }
      it { expect(p.tool_calling?).to be true }
      it { expect(p.history_policy).to eq(:none) }
      it { expect(p.default_options[:temperature]).to eq(0.2) }
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
      %w[gemma4:12b deepseek-r1:7b qwen3:4b llama3.2:3b].each do |m|
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
      profile = described_class.for("llama3.2:3b")
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

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Options do
  describe "expanded options" do
    it "accepts all new option keys" do
      opts = described_class.new(
        temperature: 0.5, num_predict: 100, stop: ["END"],
        mirostat: 2, mirostat_tau: 5.0, mirostat_eta: 0.1,
        presence_penalty: 0.5, frequency_penalty: -0.3,
        typical_p: 0.9, tfs_z: 1.0, num_thread: 4
      )

      hash = opts.to_h
      expect(hash[:num_predict]).to eq(100)
      expect(hash[:stop]).to eq(["END"])
      expect(hash[:mirostat]).to eq(2)
      expect(hash[:presence_penalty]).to eq(0.5)
      expect(hash[:frequency_penalty]).to eq(-0.3)
      expect(hash[:typical_p]).to eq(0.9)
    end

    it "validates mirostat values" do
      expect { described_class.new(mirostat: 3) }.to raise_error(ArgumentError, /mirostat/)
    end

    it "validates presence_penalty range" do
      expect { described_class.new(presence_penalty: 3.0) }.to raise_error(ArgumentError, /presence_penalty/)
    end

    it "validates stop is array" do
      expect { described_class.new(stop: "not array") }.to raise_error(ArgumentError, /stop/)
    end
  end
end

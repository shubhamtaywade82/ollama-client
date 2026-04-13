# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::JsonFragmentExtractor do
  describe ".call" do
    it "raises when text is nil" do
      expect { described_class.call(nil) }.to raise_error(Ollama::InvalidJSONError, /Empty response body/)
    end

    it "raises when text is empty" do
      expect { described_class.call("") }.to raise_error(Ollama::InvalidJSONError, /Empty response body/)
    end

    it "returns a bare object when the whole string is valid JSON" do
      expect(described_class.call('{"answer":42}')).to eq('{"answer":42}')
    end

    it "returns a bare array when the whole string is valid JSON" do
      expect(described_class.call("[1,2,3]")).to eq("[1,2,3]")
    end

    it "extracts the first object from leading prose" do
      text = 'Here you go: {"x":1} trailing'
      expect(described_class.call(text)).to eq('{"x":1}')
    end

    it "extracts nested objects" do
      text = 'prefix {"outer":{"inner":true}} suffix'
      expect(described_class.call(text)).to eq('{"outer":{"inner":true}}')
    end

    it "raises when no JSON start token exists" do
      expect { described_class.call("no braces here") }
        .to raise_error(Ollama::InvalidJSONError, /No JSON found/)
    end

    it "raises when braces are unbalanced" do
      expect { described_class.call("{\"a\":1") }.to raise_error(Ollama::InvalidJSONError, /Incomplete JSON/)
    end

    context "when the string looks like JSON but the full parse fails" do
      it "falls back to balanced extraction of the first value" do
        text = '{"a":1} trailing junk'
        expect(described_class.call(text)).to eq('{"a":1}')
      end
    end

    context "with escaped quotes in JSON string values" do
      it "does not treat escaped quotes as fragment boundaries" do
        text = '{"msg":"say \"hi\""}'
        expect(described_class.call(text)).to eq(text)
      end
    end
  end
end

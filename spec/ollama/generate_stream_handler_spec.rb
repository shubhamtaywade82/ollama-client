# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::GenerateStreamHandler do
  def stream_response(*chunks)
    instance_double(Net::HTTPResponse, read_body: nil).tap do |res|
      allow(res).to receive(:read_body) do |&block|
        chunks.each { |c| block.call(c) }
      end
    end
  end

  describe ".call" do
    it "appends response tokens to the accumulator" do
      res = stream_response(%({"response":"he","done":false}\n), %({"response":"llo","done":true}\n))
      acc = +""
      described_class.call(res, {}, acc)
      expect(acc).to eq("hello")
    end

    it "invokes on_token for each token" do
      res = stream_response(%({"response":"a","done":false}\n))
      tokens = []
      described_class.call(res, { on_token: ->(t) { tokens << t } }, +"")
      expect(tokens).to eq(["a"])
    end

    it "invokes on_complete when done is true" do
      res = stream_response(%({"response":"x","done":true}\n))
      completed = false
      described_class.call(res, { on_complete: -> { completed = true } }, +"")
      expect(completed).to be true
    end

    it "raises StreamError and notifies on_error when the line contains error" do
      res = stream_response(%({"error":"model failed"}\n))
      errors = []
      expect do
        described_class.call(res, { on_error: ->(e) { errors << e } }, +"")
      end.to raise_error(Ollama::StreamError, /model failed/)
      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(Ollama::StreamError)
    end

    it "reassembles lines split across chunks" do
      res = stream_response('{"response":"', "ab", '","done":true}', "\n")
      acc = +""
      described_class.call(res, {}, acc)
      expect(acc).to eq("ab")
    end

    it "ignores malformed JSON lines" do
      res = stream_response("not json\n", %({"response":"ok","done":true}\n))
      acc = +""
      described_class.call(res, {}, acc)
      expect(acc).to eq("ok")
    end

    it "skips blank lines" do
      res = stream_response("\n", %({"response":"z","done":true}\n))
      acc = +""
      described_class.call(res, {}, acc)
      expect(acc).to eq("z")
    end
  end
end

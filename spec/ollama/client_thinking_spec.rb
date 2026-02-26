# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client do
  describe "#generate thinking" do
    let(:client) { described_class.new }

    before do
      Ollama::Config.new
    end

    it "raises UnsupportedThinkingModel if model is not reasoning-capable" do
      expect do
        client.generate(
          model: "llama3",
          prompt: "Decide",
          think: true
        )
      end.to raise_error(Ollama::UnsupportedThinkingModel, /not marked as reasoning-capable/)
    end

    it "returns reasoning and final when both are enabled" do
      stub_request(:post, /generate/)
        .to_return(
          body: {
            response: "<think>\nanalysis\n</think>\nWAIT TEXT"
          }.to_json
        )

      result = client.generate(
        model: "deepseek-r1",
        prompt: "Decide",
        think: true,
        return_reasoning: true
      )

      expect(result["reasoning"]).to eq("analysis")
      expect(result["final"]).to eq("WAIT TEXT")
    end

    it "respects schemas when return_reasoning is enabled" do
      schema = {
        "type" => "object",
        "required" => ["decision"],
        "properties" => {
          "decision" => { "type" => "string" }
        }
      }

      stub_request(:post, /generate/)
        .to_return(
          body: {
            response: "<think>\nthinking process...\n</think>\n{\"decision\":\"BUY\"}"
          }.to_json
        )

      result = client.generate(
        model: "deepseek-r1",
        prompt: "Should I buy?",
        schema: schema,
        think: true,
        return_reasoning: true
      )

      expect(result["reasoning"]).to eq("thinking process...")
      expect(result["final"]["decision"]).to eq("BUY")
    end

    it "returns empty reasoning if response is not structured with think tags" do
      stub_request(:post, /generate/)
        .to_return(
          body: {
            response: "just returning text"
          }.to_json
        )

      result = client.generate(
        model: "deepseek-r1",
        prompt: "Decide",
        think: true,
        return_reasoning: true
      )

      expect(result["reasoning"]).to eq("")
      expect(result["final"]).to eq("just returning text")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client, "model info (VCR)", :vcr do
  let(:client) { vcr_client }

  describe "#list_models" do
    it "returns the Cloud model catalog", vcr: { cassette_name: "model_info/list_models_returns_catalog" } do
      models = client.list_models

      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.first).to include("name")
    end
  end

  describe "#show_model" do
    it "returns details with a Capabilities-derived capability hash",
       vcr: { cassette_name: "model_info/show_model_returns_details" } do
      details = client.show_model(model: VCRClientHelper::CLOUD_MODEL)

      expect(details).to be_a(Hash)
      expect(details["details"]["family"]).to eq("gptoss")
      # show_model overwrites the server's raw "capabilities" array (which for
      # this model is ["completion","tools","thinking"]) with
      # Ollama::Capabilities.for's heuristic hash. The "gptoss" family isn't in
      # Capabilities::TOOLS_FAMILIES/THINKING_MODELS yet, so both come back
      # false here despite the server saying otherwise — a known accuracy gap
      # (see docs/RUBYLLM_ADOPTION_MATRIX.md E3), not a VCR/test bug.
      expect(details["capabilities"]).to eq(
        "tools" => false, "thinking" => false, "vision" => false, "embeddings" => false
      )
    end
  end

  describe "#version" do
    it "returns a version string", vcr: { cassette_name: "model_info/version_returns_string" } do
      expect(client.version).to be_a(String)
    end
  end
end

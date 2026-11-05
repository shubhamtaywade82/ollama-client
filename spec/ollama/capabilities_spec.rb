# frozen_string_literal: true

require "spec_helper"
require "ollama_client"

RSpec.describe Ollama::Capabilities do
  describe ".for" do
    it "accurately maps a generic Llama tool-capable model" do
      model_info = {
        "name" => "qwen3.5:4b",
        "details" => { "families" => ["llama"] }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => true,
                             "thinking" => false,
                             "vision" => false,
                             "embeddings" => false
                           })
    end

    it "accurately excludes codellama from tools despite llama family" do
      model_info = {
        "name" => "codellama:7b",
        "details" => { "families" => ["llama"] }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => false,
                             "thinking" => false,
                             "vision" => false,
                             "embeddings" => false
                           })
    end

    it "accurately maps a thinking model" do
      model_info = {
        "name" => "deepseek-r1:8b",
        "details" => { "families" => ["llama"] }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => true,
                             "thinking" => true,
                             "vision" => false,
                             "embeddings" => false
                           })
    end

    it "accurately maps a vision model via family" do
      model_info = {
        "name" => "llava:13b",
        "details" => { "families" => ["llava"] }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => false,
                             "thinking" => false,
                             "vision" => true,
                             "embeddings" => false
                           })
    end

    it "accurately maps an embedding model" do
      model_info = {
        "name" => "nomic-embed-text:latest",
        "details" => { "families" => ["nomic-bert"] }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => false,
                             "thinking" => false,
                             "vision" => false,
                             "embeddings" => true
                           })
    end

    it "handles empty or malformed details block gracefully" do
      model_info = { "name" => "unknown" }
      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => false,
                             "thinking" => false,
                             "vision" => false,
                             "embeddings" => false
                           })
    end

    it "infers from 'family' when 'families' is missing" do
      model_info = {
        "name" => "qwen2.5:0.5b",
        "details" => { "family" => "qwen2" }
      }

      result = described_class.for(model_info)

      expect(result["tools"]).to be true
    end

    it "prefers server-provided capabilities array over name heuristics" do
      model_info = {
        "name" => "custom-model",
        "capabilities" => %w[completion tools thinking],
        "details" => { "family" => "unknown_family" }
      }

      result = described_class.for(model_info)

      expect(result).to eq({
                             "tools" => true,
                             "thinking" => true,
                             "vision" => false,
                             "embeddings" => false
                           })
    end

    # Client#show_model injects a derived "capabilities" Hash into the payload
    # it returns. Re-deriving from that payload used to drop the server-declared
    # values (a Hash is not the server's Array form), silently degrading to
    # name/family inference — and /api/show payloads carry no top-level "name",
    # so name-based caps (thinking) flipped to false. Caught by the live-server
    # conformance job (capabilities_show_parity FAIL, CI run 41970071523).
    it "is idempotent over a show_model payload that already carries derived capabilities" do
      list_entry = {
        "name" => "qwen3:0.6b",
        "capabilities" => %w[completion tools thinking],
        "details" => { "family" => "qwen3" }
      }
      derived = described_class.for(list_entry)
      show_payload = { "details" => { "family" => "qwen3" }, "capabilities" => derived }

      rederived = described_class.for(show_payload)

      expect(rederived).to eq(derived)
    end

    it "does not mistake an unrelated Hash capabilities key for derived capabilities" do
      model_info = {
        "name" => "qwen3:0.6b",
        "capabilities" => { "unrelated" => "shape" },
        "details" => { "family" => "qwen3" }
      }

      result = described_class.for(model_info)

      expect(result["thinking"]).to be(true) # name regex path, not the unrelated Hash
    end
  end
end

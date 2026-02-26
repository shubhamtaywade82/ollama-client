# frozen_string_literal: true

require "spec_helper"
require "ollama_client"

RSpec.describe Ollama::Capabilities do
  describe ".for" do
    it "accurately maps a generic Llama tool-capable model" do
      model_info = {
        "name" => "llama3.1:8b",
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
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Config do
  describe "#initialize" do
    it "sets safe defaults" do
      original_api_keys = ENV.fetch("OLLAMA_API_KEYS", nil)
      original_api_key = ENV.fetch("OLLAMA_API_KEY", nil)
      ENV.delete("OLLAMA_API_KEYS")
      ENV.delete("OLLAMA_API_KEY")

      config = described_class.new
      expect(config.base_url).to eq("http://localhost:11434")
      expect(config.model).to eq("qwen3.5:4b")
      expect(config.timeout).to eq(30)
      expect(config.retries).to eq(2)
      expect(config.strict_json).to be(true)
      expect(config.temperature).to eq(0.2)
      expect(config.top_p).to eq(0.9)
      expect(config.num_ctx).to eq(8192)
      expect(config.api_key).to be_nil

      ENV["OLLAMA_API_KEYS"] = original_api_keys if original_api_keys
      ENV["OLLAMA_API_KEY"] = original_api_key if original_api_key
    end
  end

  describe "#apply_auth_to" do
    around do |example|
      original_api_keys = ENV.fetch("OLLAMA_API_KEYS", nil)
      original_api_key = ENV.fetch("OLLAMA_API_KEY", nil)
      ENV.delete("OLLAMA_API_KEYS")
      ENV.delete("OLLAMA_API_KEY")

      example.run

      ENV["OLLAMA_API_KEYS"] = original_api_keys if original_api_keys
      ENV["OLLAMA_API_KEY"] = original_api_key if original_api_key
    end

    it "sets Authorization Bearer header when api_key is set" do
      config = described_class.new
      config.api_key = "secret"
      req = Net::HTTP::Post.new(URI("http://localhost/api/chat"))
      config.apply_auth_to(req)
      expect(req["Authorization"]).to eq("Bearer secret")
    end

    it "does not set Authorization when api_key is nil" do
      config = described_class.new
      req = Net::HTTP::Post.new(URI("http://localhost/api/chat"))
      config.apply_auth_to(req)
      expect(req["Authorization"]).to be_nil
    end

    it "does not set Authorization when api_key is empty string" do
      config = described_class.new
      config.api_key = "  "
      req = Net::HTTP::Post.new(URI("http://localhost/api/chat"))
      config.apply_auth_to(req)
      expect(req["Authorization"]).to be_nil
    end
  end
end

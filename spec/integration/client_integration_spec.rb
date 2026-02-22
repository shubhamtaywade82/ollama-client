# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client, type: :integration do
  before do
    skip "Skipping integration tests. Set OLLAMA_INTEGRATION=1 to run them." if ENV["OLLAMA_INTEGRATION"] != "1"
  end

  let(:client) do
    Ollama::Client.new(config: Ollama::Config.new.tap do |c|
      c.model = "llama3.2" # Adjust if your local model differs
      c.timeout = 60 # Allow longer timeouts for real generation
    end)
  end

  it "generates a simple text response" do
    response = client.generate(prompt: "Say hello world in exactly two words.")
    expect(response).to be_a(String)
    expect(response.downcase).to include("hello")
  end

  it "generates a valid structured JSON response" do
    schema = {
      "type" => "object",
      "required" => %w[greeting confidence],
      "properties" => {
        "greeting" => { "type" => "string" },
        "confidence" => { "type" => "number" }
      }
    }

    result = client.generate(
      prompt: "Say hi and report a confidence score between 0 and 1.",
      schema: schema
    )

    expect(result).to be_a(Hash)
    expect(result["greeting"]).to be_a(String)
    expect(result["confidence"]).to be_a(Numeric)
  end

  it "streams tokens via hooks" do
    tokens = []

    client.generate(
      prompt: "Count from 1 to 5.",
      hooks: {
        on_token: ->(token) { tokens << token }
      }
    )

    expect(tokens).not_to be_empty
    joined = tokens.join.downcase
    expect(joined).to include("1")
    expect(joined).to include("5")
  end

  it "handles pull dynamically if model is missing" do
    # we simulate missing model by requesting a tiny one that might not be locally cached
    # explicitly dropping failure here but we expect the client to automatically pull it and then succeed.
    tiny_model = "all-minilm"

    # We allow the test to take some time, but this tests the missing model handler
    result = client.generate(prompt: "Hello", model: tiny_model)
    expect(result).not_to be_empty
  end
end

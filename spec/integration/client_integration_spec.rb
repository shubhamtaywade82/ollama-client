# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client, type: :integration do
  before do
    skip "Skipping integration tests. Set OLLAMA_INTEGRATION=1 to run them." if ENV["OLLAMA_INTEGRATION"] != "1"
  end

  let(:client) do
    Ollama::Client.new(config: Ollama::Config.new.tap do |c|
      c.model = "llama3.1:8b" # Adjust if your local model differs
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

  it "raises NotFoundError for a non-existent model" do
    # A truly non-existent model name should trigger NotFoundError → auto-pull attempt → failure
    expect do
      client.generate(prompt: "Hello", model: "this-model-does-not-exist-xyz-99999")
    end.to raise_error(Ollama::Error) # pull will also fail for a bogus model
  end

  it "lists available models via tags endpoint" do
    models = client.list_models
    expect(models).to be_a(Array)
    expect(models).not_to be_empty
  end
end

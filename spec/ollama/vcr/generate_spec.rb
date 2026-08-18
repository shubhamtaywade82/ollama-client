# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client, "#generate (VCR)", :vcr do
  let(:client) { vcr_client }

  it "returns a plain text completion", vcr: { cassette_name: "generate/plain_text_completion" } do
    response = client.generate(prompt: "Say hello world in exactly two words.")

    expect(response).to be_a(String)
    expect(response.downcase).to include("hello")
  end

  it "returns parsed JSON when schema: is given", vcr: { cassette_name: "generate/schema_returns_parsed_json" } do
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

  it "includes a context key in return_meta output", vcr: { cassette_name: "generate/returns_context" } do
    result = client.generate(prompt: "Remember the number 42.", return_meta: true)

    # return_meta always includes a "context" key, but Ollama Cloud's
    # gpt-oss:20b (Harmony-format, chat-tuned) doesn't return the legacy
    # raw-continuation "context" array — it's nil here. Real, observed
    # behavior: the deprecated context param isn't universally supported,
    # even though the client always threads it through if given.
    expect(result).to have_key("context")
    expect(result["context"]).to be_nil
    expect(result["data"]).to be_a(String)
  end

  it "streams tokens via the on_token hook", vcr: { cassette_name: "generate/streams_via_on_token" } do
    tokens = []

    client.generate(
      prompt: "Count from 1 to 5.",
      hooks: { on_token: ->(token) { tokens << token } }
    )

    expect(tokens).not_to be_empty
    joined = tokens.join.downcase
    expect(joined).to include("1")
    expect(joined).to include("5")
  end
end

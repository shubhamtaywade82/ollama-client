# frozen_string_literal: true

require "spec_helper"

# Real Ollama Cloud responses, recorded once into spec/cassettes and replayed
# from then on — see spec/support/vcr.rb for how to re-record.
RSpec.describe Ollama::Client, "#chat (VCR)", :vcr do
  let(:client) { vcr_client }

  it "returns an assistant response for a basic prompt", vcr: { cassette_name: "chat/basic_prompt" } do
    response = client.chat(messages: [{ role: "user", content: "Say the single word: pong" }])

    expect(response).to be_a(Ollama::Response)
    expect(response.done?).to be(true)
    expect(response.message.role).to eq("assistant")
    expect(response.message.content.downcase).to include("pong")
  end

  it "separates reasoning from the final answer when think: true",
     vcr: { cassette_name: "chat/think_true_separates_reasoning" } do
    response = client.chat(
      messages: [{ role: "user", content: "What is 2 + 2? Answer with just the number." }],
      think: true
    )

    expect(response.message.thinking).to be_a(String)
    expect(response.message.thinking).not_to be_empty
    expect(response.message.content).to include("4")
  end

  it "calls a provided tool when the prompt requires it", vcr: { cassette_name: "chat/calls_provided_tool" } do
    tools = [
      {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get the current weather for a city",
          parameters: {
            type: "object",
            properties: { city: { type: "string", description: "City name" } },
            required: ["city"]
          }
        }
      }
    ]

    response = client.chat(
      messages: [
        { role: "user",
          content: "Use the get_weather tool to look up the weather in Paris. You must call the tool, " \
                   "do not answer from your own knowledge." }
      ],
      tools: tools
    )

    tool_call = response.message.tool_calls&.first
    expect(tool_call).not_to be_nil
    expect(tool_call.name).to eq("get_weather")
    expect(tool_call.arguments["city"]).to match(/paris/i)
  end

  it "returns format:-influenced content that the caller must parse/validate themselves",
     vcr: { cassette_name: "chat/format_schema_returns_json" } do
    schema = {
      "type" => "object",
      "required" => ["answer"],
      "properties" => { "answer" => { "type" => "string" } }
    }

    response = client.chat(
      messages: [{ role: "user", content: "What is the capital of France? Respond in JSON." }],
      format: schema
    )

    # Real, observed behavior: unlike generate(schema:), chat(format:) does not
    # run the response through SchemaValidator/repair (see API_CONTRACT.md and
    # docs/RUBYLLM_ADOPTION_MATRIX.md C3). The model here wrapped its answer in
    # a ```json fence and used its own key ("capital") instead of the schema's
    # required "answer" — content the caller has to fence-strip, parse, and
    # validate themselves. This test documents that gap rather than papering
    # over it.
    fenced = response.message.content
    unfenced = fenced.sub(/\A```(?:json)?\n/, "").sub(/```\z/, "")
    parsed = JSON.parse(unfenced)

    expect(parsed.values.join).to match(/paris/i)
  end

  it "streams tokens via the on_token hook", vcr: { cassette_name: "chat/streams_via_on_token" } do
    tokens = []

    client.chat(
      messages: [{ role: "user", content: "Count from 1 to 5, one number per line." }],
      hooks: { on_token: ->(token) { tokens << token } }
    )

    expect(tokens).not_to be_empty
    joined = tokens.join
    expect(joined).to include("1")
    expect(joined).to include("5")
  end
end

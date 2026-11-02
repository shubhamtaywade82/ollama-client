# frozen_string_literal: true

# Reproduction for maintenance findings (2026-11-01 gap audit vs the official
# docs/api.md, byte-identical to the snapshot of 2026-10-31):
#
# (a) Serializers::Generate never puts the documented `template` request field
#     on the wire (docs/api.md "Generate a completion" -> Parameters ->
#     `template`: "the prompt template to use (overrides what is defined in
#     the Modelfile)").
# (b) `generate(tools:)` is accepted by the public API (API_CONTRACT.md v1.4.0
#     generate signature lists `tools: nil`), but `generate_with_params` never
#     forwards `params.tools` to the request preparer, so tools are silently
#     dropped. This spec pins the wire contract: tools are forwarded verbatim
#     (stock Ollama servers ignore unknown fields; gateways that support
#     generation-side tools can use them).
require "spec_helper"

RSpec.describe Ollama::Client do
  let(:client) { described_class.new(config: Ollama::Config.new) }

  it "sends the documented template field in the /api/generate request body" do
    request_body = nil
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "ok", done: true }.to_json)

    client.generate(prompt: "hello", template: "{{ .Prompt }}")

    expect(request_body).to include("template" => "{{ .Prompt }}")
  end

  it "sends tools in the /api/generate request body instead of dropping them" do
    request_body = nil
    tools = [{ "type" => "function", "function" => { "name" => "get_weather" } }]
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "ok", done: true }.to_json)

    client.generate(prompt: "hello", tools: tools)

    expect(request_body).to include("tools" => tools)
  end

  it "omits template and tools keys when not provided" do
    request_body = nil
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "ok", done: true }.to_json)

    client.generate(prompt: "hello")

    expect(request_body).not_to include("template")
    expect(request_body).not_to include("tools")
  end
end

# frozen_string_literal: true

# Reproduction for the maintenance gap audit (2026-11-02, vs official
# docs/api.md and API_CONTRACT.md v1.4.0):
#
# `generate(tools:)` is accepted by the public API (API_CONTRACT.md v1.4.0
# generate signature lists `tools: nil`) and forwarded into Params::Generate,
# but it never reaches the wire: Client#generate_with_params does not pass
# params.tools to call_generate_api, RequestPreparer#build_request does not
# accept it, and Serializers::Generate never writes body[:tools] (RAW_KEYS =
# system/suffix/raw/context/template/logprobs/top_logprobs only). Same defect
# class as the F-1 context fix (#46).
#
# The official API does not document tool calling for /api/generate; stock
# servers ignore unknown request fields, so forwarding is additive and safe
# (noted in API_CONTRACT.md under Generate).
require "spec_helper"

RSpec.describe Ollama::Client do
  let(:client) { described_class.new(config: Ollama::Config.new) }

  it "sends tools in the /api/generate request body instead of dropping them" do
    request_body = nil
    tools = [{ "type" => "function", "function" => { "name" => "get_weather" } }]
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "ok", done: true }.to_json)

    client.generate(prompt: "hello", tools: tools)

    expect(request_body).to include("tools" => tools)
  end

  it "omits the tools key when not provided" do
    request_body = nil
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(status: 200, body: { response: "ok", done: true }.to_json)

    client.generate(prompt: "hello")

    expect(request_body).not_to include("tools")
  end
end

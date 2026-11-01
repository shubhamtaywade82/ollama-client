# frozen_string_literal: true

# Reproduction for maintenance finding (2026-10-31 baseline run):
# `generate(context:)` is documented in API_CONTRACT.md ("accepts the context
# array returned by a previous generate call ... for /api/generate-side
# conversational memory") and in docs/api.md (request field "context"), but
# Serializers::Generate never copies raw_options[:context] onto the wire body,
# so the context array is silently dropped from the request.
require "spec_helper"

RSpec.describe Ollama::Client do
  let(:client) { described_class.new(config: Ollama::Config.new) }

  it "sends the context array in the /api/generate request body" do
    request_body = nil
    stub_request(:post, "http://localhost:11434/api/generate")
      .with { |req| request_body = JSON.parse(req.body) }
      .to_return(
        status: 200,
        body: { response: "ok", done: true, context: [1, 2, 3] }.to_json
      )

    client.generate(prompt: "continue", context: [9, 8, 7], return_meta: true)

    expect(request_body).to include("context" => [9, 8, 7])
  end
end

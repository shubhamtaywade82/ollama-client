# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client, "#generate" do
  let(:client) { described_class.new(config: config) }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.model = "test-model"
      c.retries = 2
      c.timeout = 5
    end
  end
  let(:schema) do
    {
      "type" => "object",
      "required" => ["test"],
      "properties" => {
        "test" => { "type" => "string" }
      }
    }
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "successful requests" do
    it "returns parsed and validated JSON response" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(
          body: hash_including(
            model: "test-model",
            prompt: anything,
            stream: false,
            format: schema
          )
        )
        .to_return(
          status: 200,
          body: { response: '{"test":"value"}' }.to_json
        )

      result = client.generate(prompt: "test prompt", schema: schema)

      expect(result).to eq("test" => "value")
    end

    it "allows model override" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/generate")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: { response: '{"test":"value"}' }.to_json
        )

      client.generate(prompt: "test", schema: schema, model: "custom-model")

      expect(request_body["model"]).to eq("custom-model")
    end

    it "includes format parameter when schema is provided" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/generate")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: { response: '{"test":"value"}' }.to_json
        )

      client.generate(prompt: "test", schema: schema)

      expect(request_body["format"]).to eq(schema)
    end

    it "uses config defaults for temperature, top_p, num_ctx" do
      request_body = nil
      stub_request(:post, "http://localhost:11434/api/generate")
        .with { |req| request_body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: { response: '{"test":"value"}' }.to_json
        )

      client.generate(prompt: "test", schema: schema)

      expect(request_body["temperature"]).to eq(config.temperature)
      expect(request_body["top_p"]).to eq(config.top_p)
      expect(request_body["num_ctx"]).to eq(config.num_ctx)
    end
  end

  describe "error handling" do
    context "when model is not found (404)" do
      it "raises NotFoundError with model suggestions" do
        # First request fails with 404
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 404, body: "Not Found")

        # Model suggestion request succeeds
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(
            status: 200,
            body: {
              models: [
                { name: "test-model-v2" },
                { name: "other-model" }
              ]
            }.to_json
          )

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::NotFoundError) do |error|
          expect(error.requested_model).to eq("test-model")
          expect(error.suggestions).to include("test-model-v2")
        end
      end

      it "does not retry 404 errors" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 404, body: "Not Found")

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: { models: [] }.to_json)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::NotFoundError)

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").once
      end

      context "when per-call model is provided" do
        it "uses the per-call model for requested_model" do
          stub_request(:post, "http://localhost:11434/api/generate")
            .to_return(status: 404, body: "Not Found")

          stub_request(:get, "http://localhost:11434/api/tags")
            .to_return(status: 200, body: { models: [] }.to_json)

          expect do
            client.generate(prompt: "test", schema: schema, model: "custom-model")
          end.to raise_error(Ollama::NotFoundError) do |error|
            expected_requested_model = "custom-model"
            actual_requested_model = error.requested_model
            expect(actual_requested_model).to eq(expected_requested_model)
          end
        end
      end
    end

    context "when server returns 500 (retryable)" do
      it "retries up to config.retries times" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 500, body: "Internal Server Error")
          .times(config.retries + 1)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::RetryExhaustedError)

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate")
          .times(config.retries + 1)
      end

      it "succeeds on retry" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(
            { status: 500, body: "Internal Server Error" },
            { status: 200, body: { response: '{"test":"value"}' }.to_json }
          )

        result = client.generate(prompt: "test", schema: schema)

        expect(result).to eq("test" => "value")
        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").twice
      end
    end

    context "when server returns 400 (non-retryable)" do
      it "raises HTTPError immediately without retrying" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 400, body: "Bad Request")

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::HTTPError) do |error|
          expect(error.status_code).to eq(400)
          expect(error.retryable?).to be false
        end

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").once
      end
    end

    context "when request times out" do
      it "retries on timeout" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_timeout
          .times(config.retries + 1)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::RetryExhaustedError)

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate")
          .times(config.retries + 1)
      end
    end

    context "when response is invalid JSON" do
      it "retries on InvalidJSONError" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(
            { status: 200, body: "not json" },
            { status: 200, body: { response: '{"test":"value"}' }.to_json }
          )

        result = client.generate(prompt: "test", schema: schema)

        expect(result).to eq("test" => "value")
        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").twice
      end
    end

    context "when response violates schema" do
      it "retries on SchemaViolationError" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(
            { status: 200, body: { response: '{"test":123}' }.to_json }, # Wrong type
            { status: 200, body: { response: '{"test":"value"}' }.to_json }
          )

        result = client.generate(prompt: "test", schema: schema)

        expect(result).to eq("test" => "value")
        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").twice
      end
    end

    context "when connection fails" do
      it "retries on connection errors" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_raise(SocketError.new("Connection refused"))
          .times(config.retries + 1)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::RetryExhaustedError)

        expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate")
          .times(config.retries + 1)
      end
    end
  end

  describe "JSON parsing edge cases" do
    it "handles JSON wrapped in markdown code blocks" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(
          status: 200,
          body: { response: "```json\n{\"test\":\"value\"}\n```" }.to_json
        )

      result = client.generate(prompt: "test", schema: schema)

      expect(result).to eq("test" => "value")
    end

    it "handles plain JSON in response" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(
          status: 200,
          body: { response: '{"test":"value"}' }.to_json
        )

      result = client.generate(prompt: "test", schema: schema)

      expect(result).to eq("test" => "value")
    end

    it "handles non-JSON prefix/suffix noise" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(
          status: 200,
          body: { response: "Here you go:\n{\"test\":\"value\"}\nDone." }.to_json
        )

      result = client.generate(prompt: "test", schema: schema)

      expect(result).to eq("test" => "value")
    end
  end

  describe "strict mode" do
    it "does not retry on schema violation when strict" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(
          { status: 200, body: { response: '{"test":123}' }.to_json }, # Wrong type
          { status: 200, body: { response: '{"test":"value"}' }.to_json }
        )

      expect do
        client.generate(prompt: "test", schema: schema, strict: true)
      end.to raise_error(Ollama::SchemaViolationError)

      expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").once
    end

    it "does not retry on invalid JSON when strict" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(
          { status: 200, body: { response: "not json" }.to_json },
          { status: 200, body: { response: '{"test":"value"}' }.to_json }
        )

      expect do
        client.generate(prompt: "test", schema: schema, strict: true)
      end.to raise_error(Ollama::InvalidJSONError)

      expect(WebMock).to have_requested(:post, "http://localhost:11434/api/generate").once
    end

    it "provides a generate_strict! convenience method" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 200, body: { response: '{"test":"value"}' }.to_json)

      result = client.generate_strict!(prompt: "test", schema: schema)
      expect(result).to eq("test" => "value")
    end
  end
end

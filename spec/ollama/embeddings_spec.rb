# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Embeddings do
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "http://localhost:11434"
      c.timeout = 5
    end
  end
  let(:embeddings) { described_class.new(config) }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  after do
    WebMock.reset!
  end

  describe "#embed" do
    context "with single text input" do
      it "returns embedding vector" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .with(
            body: hash_including(
              model: "nomic-embed-text:latest",
              input: "What is Ruby?"
            )
          )
          .to_return(
            status: 200,
            body: {
              embeddings: [[0.1, 0.2, 0.3, 0.4, 0.5]]
            }.to_json
          )

        result = embeddings.embed(model: "nomic-embed-text:latest", input: "What is Ruby?")

        expect(result).to be_an(Array)
        expect(result).to eq([0.1, 0.2, 0.3, 0.4, 0.5])
      end
    end

    context "with array input" do
      it "returns array of embedding vectors" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .with(
            body: hash_including(
              model: "nomic-embed-text:latest",
              input: ["What is Ruby?", "What is Python?"]
            )
          )
          .to_return(
            status: 200,
            body: {
              embeddings: [[0.1, 0.2], [0.3, 0.4]]
            }.to_json
          )

        result = embeddings.embed(
          model: "nomic-embed-text:latest",
          input: ["What is Ruby?", "What is Python?"]
        )

        expect(result).to be_an(Array)
        expect(result.first).to be_an(Array)
        expect(result.length).to eq(2)
      end
    end

    context "when handling errors" do
      it "raises NotFoundError on 404" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(status: 404, body: "Not Found")

        expect do
          embeddings.embed(model: "nonexistent", input: "test")
        end.to raise_error(Ollama::NotFoundError)
      end

      it "raises HTTPError on other HTTP errors" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(status: 500, body: "Internal Server Error")

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::HTTPError)
      end

      it "raises InvalidJSONError on malformed JSON response" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(status: 200, body: "not json")

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::InvalidJSONError)
      end

      it "raises TimeoutError on timeout" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_timeout

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::TimeoutError)
      end

      it "raises Error on connection failure" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_raise(Errno::ECONNREFUSED)

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::Error, /Connection failed/)
      end

      it "raises Error when embeddings are missing from response" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(
            status: 200,
            body: { other_key: "value" }.to_json
          )

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::Error, /Embeddings not found/)
      end

      it "raises Error when embeddings is empty array" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(
            status: 200,
            body: { embeddings: [] }.to_json
          )

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::Error, /Empty embedding/)
      end

      it "raises Error when embeddings contains empty array" do
        stub_request(:post, "http://localhost:11434/api/embed")
          .to_return(
            status: 200,
            body: { embeddings: [[]] }.to_json
          )

        expect do
          embeddings.embed(model: "nomic-embed-text:latest", input: "test")
        end.to raise_error(Ollama::Error, /Empty embedding/)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe Ollama::Error do
  describe "Ollama::Error" do
    it "is a StandardError" do
      expect(described_class.new).to be_a(StandardError)
    end
  end

  describe "Ollama::TimeoutError" do
    it "inherits from Error" do
      expect(Ollama::TimeoutError.new).to be_a(described_class)
    end
  end

  describe "Ollama::InvalidJSONError" do
    it "inherits from Error" do
      expect(Ollama::InvalidJSONError.new).to be_a(described_class)
    end
  end

  describe "Ollama::SchemaViolationError" do
    it "inherits from Error" do
      expect(Ollama::SchemaViolationError.new).to be_a(described_class)
    end
  end

  describe "Ollama::RetryExhaustedError" do
    it "inherits from Error" do
      expect(Ollama::RetryExhaustedError.new).to be_a(described_class)
    end
  end

  describe "Ollama::HTTPError" do
    it "inherits from Error" do
      expect(Ollama::HTTPError.new("test", 500)).to be_a(described_class)
    end

    describe "#retryable?" do
      it "returns true for 5xx errors" do
        error = Ollama::HTTPError.new("Server Error", 500)
        expect(error.retryable?).to be true

        error = Ollama::HTTPError.new("Bad Gateway", 502)
        expect(error.retryable?).to be true

        error = Ollama::HTTPError.new("Service Unavailable", 503)
        expect(error.retryable?).to be true
      end

      it "returns true for 408 (Request Timeout)" do
        error = Ollama::HTTPError.new("Request Timeout", 408)
        expect(error.retryable?).to be true
      end

      it "returns true for 429 (Too Many Requests)" do
        error = Ollama::HTTPError.new("Too Many Requests", 429)
        expect(error.retryable?).to be true
      end

      it "returns false for 4xx errors (except 408, 429)" do
        error = Ollama::HTTPError.new("Bad Request", 400)
        expect(error.retryable?).to be false

        error = Ollama::HTTPError.new("Unauthorized", 401)
        expect(error.retryable?).to be false

        error = Ollama::HTTPError.new("Forbidden", 403)
        expect(error.retryable?).to be false
      end

      it "returns false for 3xx errors" do
        error = Ollama::HTTPError.new("Redirect", 301)
        expect(error.retryable?).to be false
      end
    end
  end

  describe "Ollama::NotFoundError" do
    it "inherits from HTTPError" do
      error = Ollama::NotFoundError.new("Not Found", requested_model: "test")
      expect(error).to be_a(Ollama::HTTPError)
    end

    it "has status_code 404" do
      error = Ollama::NotFoundError.new("Not Found", requested_model: "test")
      expect(error.status_code).to eq(404)
    end

    it "stores requested_model" do
      error = Ollama::NotFoundError.new("Not Found", requested_model: "test-model")
      expect(error.requested_model).to eq("test-model")
    end

    it "stores suggestions array" do
      suggestions = %w[model1 model2]
      error = Ollama::NotFoundError.new("Not Found", requested_model: "test", suggestions: suggestions)
      expect(error.suggestions).to eq(suggestions)
    end

    it "has empty suggestions by default" do
      error = Ollama::NotFoundError.new("Not Found", requested_model: "test")
      expect(error.suggestions).to eq([])
    end

    describe "#to_s" do
      it "returns base message when no suggestions" do
        error = Ollama::NotFoundError.new("Not Found", requested_model: "test-model")
        message = error.to_s
        expect(message).to include("404")
        expect(message).to include("Not Found")
        # When no suggestions, to_s just returns the base message
      end

      it "includes suggestions when available" do
        suggestions = %w[test-model-v2 test-model-v3]
        error = Ollama::NotFoundError.new("Not Found", requested_model: "test-model", suggestions: suggestions)
        message = error.to_s
        expect(message).to include("test-model")
        expect(message).to include("test-model-v2")
        expect(message).to include("test-model-v3")
        expect(message).to include("Did you mean")
      end
    end
  end
end

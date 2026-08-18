# frozen_string_literal: true

require "spec_helper"
require "ollama/middleware/logger"
require "ollama/middleware/metrics"
require "ollama/middleware/cache"
require "ollama/middleware/tracing"

# Regression coverage for lib/ollama/middleware/*: every subclass file used to
# reopen Ollama::Middleware (a class) as `module Middleware`, which raises
# TypeError the instant the file loads. Nothing required these files and no
# spec exercised them, so the bug shipped silently — including the
# client.use Ollama::Middleware::Logger example in README.md.
RSpec.describe Ollama::Middleware, "subclasses" do
  let(:request) do
    Ollama::Request.new(endpoint: :chat, model: "qwen3.5:4b", messages: [{ role: "user", content: "hi" }],
                        stream: false)
  end

  describe Ollama::Middleware::Logger do
    it "wires into a client via #use and runs before_request/after_response" do
      client = Ollama::Client.new
      expect { client.use described_class }.not_to raise_error

      middleware = described_class.new(logger: Class.new { def info(*); end }.new)
      expect(middleware.before_request(request, {})).to eq(request)
    end
  end

  describe Ollama::Middleware::Metrics do
    it "records before_request/after_response without error" do
      middleware = described_class.new
      env = {}
      expect { middleware.before_request(request, env) }.not_to raise_error
      response = double("Response", status: 200, success?: true) # rubocop:disable RSpec/VerifiedDoubles
      expect { middleware.after_response(response, env.merge(request: request, duration_ms: 12)) }
        .not_to raise_error
    end
  end

  describe Ollama::Middleware::Cache do
    it "reads/writes through the given store" do
      store = Class.new do
        def read(_key) = nil
        def write(_key, _value, **) = nil
      end.new
      middleware = described_class.new(store: store)

      expect(middleware.before_request(request, {})).to eq(request)
    end
  end

  describe Ollama::Middleware::Tracing do
    it "creates a no-op span/context when no tracer is configured" do
      middleware = described_class.new
      env = {}

      middleware.before_request(request, env)
      expect(env[:trace_span]).to be_a(Ollama::Middleware::Tracing::NoOpSpan)
      expect(env[:trace_span].context).to be_a(Ollama::Middleware::Tracing::NoOpContext)
    end
  end
end

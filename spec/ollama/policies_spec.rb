# frozen_string_literal: true

require "spec_helper"

# End-to-end coverage for the policy middleware attached via client.use.
# Policies run inside the pipeline, wrapping the transport chain; HTTP
# failures are surfaced as typed errors inside the chain by Pipeline (see
# lib/ollama/pipeline.rb) so policies can observe them.
RSpec.describe "Ollama::Policies" do
  let(:chat_url) { "http://localhost:11434/api/chat" }
  let(:client) { Ollama::Client.new }
  let(:messages) { [{ role: "user", content: "hi" }] }

  def chat_ok(content = "ok")
    { status: 200, body: { message: { role: "assistant", content: content }, done: true }.to_json }
  end

  describe Ollama::Policies::Retry do
    it "retries a failed request and succeeds" do
      retries = []
      stub_request(:post, chat_url)
        .to_timeout.then
        .to_return(chat_ok)

      client.use(described_class, max_attempts: 3, strategy: :fixed, base_delay: 0, max_delay: 0,
                                  hooks: { before_retry: ->(_r, _e, _err, attempt) { retries << attempt } })

      response = client.chat(messages: messages)

      expect(response.message.content).to eq("ok")
      expect(retries).to eq([1])
    end

    it "raises after exhausting attempts" do
      stub_request(:post, chat_url).to_timeout

      client.use(described_class, max_attempts: 2, strategy: :fixed, base_delay: 0, max_delay: 0)

      expect { client.chat(messages: messages) }.to raise_error(Ollama::TimeoutError)
    end
  end

  describe Ollama::Policies::Timeout do
    it "fires the on_timeout hook when a request times out" do
      fired = false
      stub_request(:post, chat_url).to_timeout

      client.use(described_class, hooks: { on_timeout: ->(_r, _e, _err) { fired = true } })

      expect { client.chat(messages: messages) }.to raise_error(Ollama::TimeoutError)
      expect(fired).to be true
    end

    it "passes requests through when they succeed" do
      stub_request(:post, chat_url).to_return(chat_ok)

      client.use(described_class)

      expect(client.chat(messages: messages).message.content).to eq("ok")
    end
  end

  describe Ollama::Policies::AutoPull do
    it "pulls the missing model once and retries the request" do
      stub_request(:post, chat_url)
        .to_return(
          { status: 404, body: { error: "model 'llama3.1:8b' not found" }.to_json },
          chat_ok
        )
      stub_request(:post, "http://localhost:11434/api/pull")
        .with(body: hash_including("model" => "llama3.1:8b"))
        .to_return(status: 200, body: { status: "success" }.to_json)

      client.use(described_class, allowed_patterns: ["llama3.1:*"])

      response = client.chat(messages: messages, model: "llama3.1:8b")

      expect(response.message.content).to eq("ok")
      expect(a_request(:post, "http://localhost:11434/api/pull")).to have_been_made.once
    end

    it "does not pull models outside the allowed patterns" do
      stub_request(:post, chat_url)
        .to_return(status: 404, body: { error: "model 'x' not found" }.to_json)

      client.use(described_class, allowed_patterns: ["llama3.1:*"])

      expect do
        client.chat(messages: messages, model: "some-other-model")
      end.to raise_error(Ollama::NotFoundError)
      expect(a_request(:post, "http://localhost:11434/api/pull")).not_to have_been_made
    end
  end

  describe Ollama::Policies::Fallback do
    it "tries the next model when the first fails with NotFoundError" do
      stub_request(:post, chat_url)
        .with(body: /llama3\.1:8b/)
        .to_return(status: 404, body: { error: "not found" }.to_json)
      stub_request(:post, chat_url)
        .with(body: /gemma4:31b/)
        .to_return(chat_ok)

      client.use(described_class, models: %w[llama3.1:8b gemma4:31b])

      response = client.chat(messages: messages, model: "llama3.1:8b")

      expect(response.message.content).to eq("ok")
      expect(a_request(:post, chat_url).with(body: /gemma4:31b/)).to have_been_made.once
    end

    it "raises when all fallback models fail" do
      stub_request(:post, chat_url)
        .to_return(status: 404, body: { error: "not found" }.to_json)

      client.use(described_class, models: %w[a b])

      expect { client.chat(messages: messages, model: "a") }.to raise_error(Ollama::NotFoundError)
    end
  end

  describe Ollama::Policies::CapabilityValidation do
    it "blocks tools on models that do not support tool calling" do
      client.use(described_class)

      expect do
        client.chat(messages: messages, model: "deepseek-r1:14b", tools: [{ type: "function", function: { name: "f" } }])
      end.to raise_error(Ollama::UnsupportedCapabilityError, /tools/)
    end

    it "allows requests when the model supports the requested capability" do
      stub_request(:post, chat_url).to_return(chat_ok)

      client.use(described_class)

      response = client.chat(messages: messages, model: "qwen3:8b", tools: [{ type: "function", function: { name: "f" } }])
      expect(response.message.content).to eq("ok")
    end
  end

  describe Ollama::Policies::RateLimit do
    it "passes requests through when under the limit" do
      stub_request(:post, chat_url).to_return(chat_ok)

      client.use(described_class, requests_per_second: 1000, requests_per_minute: 60_000, burst: 1000)

      expect(client.chat(messages: messages).message.content).to eq("ok")
    end
  end

  describe Ollama::Policies::RepairJson do
    it "repairs a truncated JSON response body" do
      stub_request(:post, chat_url)
        .to_return(status: 200, body: '{"message":{"role":"assistant","content":"hi"')

      client.use(described_class)

      expect(client.chat(messages: messages).message.content).to eq("hi")
    end
  end

  describe Ollama::Policies::SchemaRepair do
    let(:schema) do
      {
        "type" => "object",
        "required" => ["city"],
        "properties" => { "city" => { "type" => "string" } }
      }
    end

    it "fills missing required fields in structured generate output" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 200, body: {
          response: "{}",
          done: true
        }.to_json)

      client.use(described_class)

      parsed = client.generate(prompt: "weather?", model: "qwen3:8b", schema: schema)

      expect(parsed).to eq("city" => "")
    end
  end
end

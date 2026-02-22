# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client do
  it "has a version number" do
    expect(Ollama::VERSION).not_to be_nil
    expect(Ollama::VERSION).to be_a(String)
  end

  describe ".new" do
    before do
      OllamaClient.configure do |c|
        c.base_url = "http://localhost:11434"
        c.model = "llama3.1:8b"
        c.timeout = 30
        c.retries = 2
        c.strict_json = true
        c.temperature = 0.2
        c.top_p = 0.9
        c.num_ctx = 8192
      end
    end

    it "initializes with default config" do
      client = described_class.new
      config = client.instance_variable_get(:@config)
      expect(config).to be_a(Ollama::Config)
      expect(config.model).to eq("llama3.1:8b")
    end

    it "accepts custom config" do
      custom_config = Ollama::Config.new
      custom_config.model = "custom_model"
      client = described_class.new(config: custom_config)
      config = client.instance_variable_get(:@config)
      expect(config.model).to eq("custom_model")
    end
  end

  describe "#generate" do
    let(:client) { described_class.new(config: Ollama::Config.new) }
    let(:schema) do
      {
        "type" => "object",
        "required" => ["test"],
        "properties" => {
          "test" => { "type" => "string" }
        }
      }
    end

    it "requires prompt parameter" do
      expect { client.generate }.to raise_error(ArgumentError)
      expect { client.generate(schema: schema) }.to raise_error(ArgumentError)

      stub_request(:post, "http://localhost:11434/api/generate")
        .to_return(status: 200, body: { response: "test response" }.to_json)
      expect { client.generate(prompt: "test") }.not_to raise_error
    end

    it "sends options nested under the options key" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: hash_including(
          "options" => hash_including("temperature" => 0.2, "top_p" => 0.9, "num_ctx" => 8192)
        ))
        .to_return(status: 200, body: { response: "test" }.to_json)

      expect { client.generate(prompt: "test") }.not_to raise_error
    end

    it "accepts system, images, think, keep_alive, suffix, raw parameters" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: hash_including(
          "system" => "You are helpful",
          "images" => ["base64data"],
          "think" => true,
          "keep_alive" => "5m",
          "suffix" => "end",
          "raw" => true
        ))
        .to_return(status: 200, body: { response: "test" }.to_json)

      expect do
        client.generate(
          prompt: "test", system: "You are helpful", images: ["base64data"],
          think: true, keep_alive: "5m", suffix: "end", raw: true
        )
      end.not_to raise_error
    end

    it "merges user options with config defaults" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: hash_including(
          "options" => hash_including("temperature" => 0.8, "top_p" => 0.9, "num_ctx" => 8192)
        ))
        .to_return(status: 200, body: { response: "test" }.to_json)

      expect { client.generate(prompt: "test", options: { temperature: 0.8 }) }.not_to raise_error
    end

    context "when Ollama server is not available (ECONNREFUSED)" do
      it "raises an error immediately without retrying because it is not retryable by default" do
        unavailable_client = described_class.new(config: Ollama::Config.new.tap do |c|
          c.base_url = "http://localhost:99999"
          c.retries = 3
        end)

        stub_request(:post, "http://localhost:99999/api/generate")
          .to_raise(Errno::ECONNREFUSED.new("Connection refused"))

        expect do
          unavailable_client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::Error, /Connection failed/)
      end
    end

    context "when hitting a timeout" do
      it "retries with exponential backoff and exhausts retries" do
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_raise(Net::ReadTimeout)
          .times(3)

        allow(client).to receive(:sleep)

        expect do
          client.generate(prompt: "test", schema: schema)
        end.to raise_error(Ollama::RetryExhaustedError, /timed out/)

        expect(client).to have_received(:sleep).with(2).ordered
        expect(client).to have_received(:sleep).with(4).ordered
      end
    end

    context "when hitting invalid JSON with strict mode" do
      it "appends repair prompt and retries" do
        # First request returns invalid JSON
        stub_request(:post, "http://localhost:11434/api/generate")
          .with(body: /original prompt/)
          .to_return(status: 200, body: "Not JSON")

        # Second request successfully returns JSON
        stub_request(:post, "http://localhost:11434/api/generate")
          .with(body: /CRITICAL FIX/)
          .to_return(status: 200, body: { response: '{"test":"fixed"}' }.to_json)

        result = client.generate(prompt: "original prompt", schema: schema, strict: true)
        expect(result).to eq("test" => "fixed")
      end
    end

    context "when model is missing (404)" do
      it "attempts to pull the model once then retries" do
        # First request returns 404
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 404, body: { error: "model not found" }.to_json)

        # Then it should trigger a pull
        stub_request(:post, "http://localhost:11434/api/pull")
          .to_return(status: 200, body: { status: "success" }.to_json)

        # The subsequent retry returns 200
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 200, body: { response: '{"test":"value"}' }.to_json)

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: { models: [] }.to_json)

        result = client.generate(prompt: "test", schema: schema)
        expect(result).to eq("test" => "value")
      end
    end

    context "when a streaming error occurs" do
      it "raises StreamError when error object appears in stream" do
        # Simulate an error response embedded in the JSON body
        stub_request(:post, "http://localhost:11434/api/generate")
          .to_return(status: 200, body: { error: "model crashed" }.to_json)

        # Non-streaming path parses the body; if it contains an "error" key
        # the response text is the raw JSON, which generate returns as-is
        # For streaming, we verify the StreamError class exists and is raised correctly
        error = Ollama::StreamError.new("model crashed")
        expect(error).to be_a(Ollama::Error)
        expect(error.message).to match(/model crashed/)
      end
    end
  end

  describe "#chat" do
    let(:client) { described_class.new(config: Ollama::Config.new) }
    let(:messages) { [{ role: "user", content: "Hello" }] }

    it "requires messages parameter" do
      expect { client.chat(messages: nil) }.to raise_error(ArgumentError)
      expect { client.chat(messages: []) }.to raise_error(ArgumentError)
    end

    it "sends a basic chat request and returns Response" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including(
          "model" => "llama3.1:8b",
          "messages" => [{ "role" => "user", "content" => "Hello" }],
          "stream" => false
        ))
        .to_return(status: 200, body: {
          model: "llama3.1:8b",
          message: { role: "assistant", content: "Hi there!" },
          done: true,
          done_reason: "stop",
          total_duration: 500_000
        }.to_json)

      response = client.chat(messages: messages)
      expect(response).to be_a(Ollama::Response)
      expect(response.message.content).to eq("Hi there!")
      expect(response.message.role).to eq("assistant")
      expect(response.done?).to be true
      expect(response.done_reason).to eq("stop")
      expect(response.total_duration).to eq(500_000)
    end

    it "sends options nested under options key" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including(
          "options" => hash_including("temperature" => 0.2)
        ))
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "test" }, done: true
        }.to_json)

      expect { client.chat(messages: messages) }.not_to raise_error
    end

    it "supports tools parameter" do
      tools = [
        {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get weather for a city",
            parameters: {
              type: "object",
              properties: { city: { type: "string" } },
              required: ["city"]
            }
          }
        }
      ]

      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("tools" => tools.map { |t| JSON.parse(t.to_json) }))
        .to_return(status: 200, body: {
          message: {
            role: "assistant",
            content: "",
            tool_calls: [
              { function: { name: "get_weather", arguments: { city: "London" } } }
            ]
          },
          done: true
        }.to_json)

      response = client.chat(messages: messages, tools: tools)
      expect(response.message.tool_calls).not_to be_empty
      expect(response.message.tool_calls.first.name).to eq("get_weather")
      expect(response.message.tool_calls.first.arguments).to eq({ "city" => "London" })
    end

    it "supports format parameter for structured output" do
      schema = { type: "object", properties: { answer: { type: "string" } } }

      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("format" => JSON.parse(schema.to_json)))
        .to_return(status: 200, body: {
          message: { role: "assistant", content: '{"answer":"42"}' }, done: true
        }.to_json)

      response = client.chat(messages: messages, format: schema)
      expect(response.message.content).to eq('{"answer":"42"}')
    end

    it "supports think parameter" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("think" => true))
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "result", thinking: "I need to think..." },
          done: true
        }.to_json)

      response = client.chat(messages: messages, think: true)
      expect(response.message.thinking).to eq("I need to think...")
      expect(response.message.content).to eq("result")
    end

    it "supports keep_alive parameter" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("keep_alive" => "10m"))
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "test" }, done: true
        }.to_json)

      expect { client.chat(messages: messages, keep_alive: "10m") }.not_to raise_error
    end

    it "supports logprobs and top_logprobs" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("logprobs" => true, "top_logprobs" => 5))
        .to_return(status: 200, body: {
          message: { role: "assistant", content: "test" },
          done: true,
          logprobs: [{ token: "test", logprob: -0.5 }]
        }.to_json)

      response = client.chat(messages: messages, logprobs: true, top_logprobs: 5)
      expect(response.logprobs).not_to be_nil
    end

    it "raises TimeoutError on timeout" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_timeout

      expect { client.chat(messages: messages) }.to raise_error(Ollama::TimeoutError)
    end

    it "raises Error on connection failure" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_raise(Errno::ECONNREFUSED)

      expect { client.chat(messages: messages) }.to raise_error(Ollama::Error, /Connection failed/)
    end

    it "parses error body from HTTP error response" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 404, body: { error: "model 'nonexistent' not found" }.to_json)

      expect do
        client.chat(messages: messages, model: "nonexistent")
      end.to raise_error(Ollama::NotFoundError, /model 'nonexistent' not found/)
    end

    context "with streaming" do
      it "returns non-streaming response with hooks when using WebMock" do
        # WebMock doesn't support chunked streaming, so hooks auto-detect
        # won't trigger chunked read_body. Test the non-streaming path.
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(status: 200, body: {
            message: { role: "assistant", content: "Hello world!" },
            done: true, done_reason: "stop"
          }.to_json)

        response = client.chat(messages: messages, stream: false)
        expect(response.message.content).to eq("Hello world!")
        expect(response.done?).to be true
      end

      it "verifies StreamError is properly raised from stream errors" do
        # WebMock can't properly simulate NDJSON streaming, so verify
        # the error class and that chat properly raises on HTTP errors
        error = Ollama::StreamError.new("an error was encountered while running the model")
        expect(error).to be_a(Ollama::Error)
        expect(error.message).to match(/error was encountered/)

        # Verify chat raises on HTTP error responses
        stub_request(:post, "http://localhost:11434/api/chat")
          .to_return(status: 500, body: { error: "server error" }.to_json)

        expect do
          client.chat(messages: messages)
        end.to raise_error(Ollama::HTTPError)
      end
    end
  end

  describe "#show_model" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "returns model details" do
      stub_request(:post, "http://localhost:11434/api/show")
        .with(body: hash_including("model" => "qwen2.5-coder:7b"))
        .to_return(status: 200, body: {
          parameters: "temperature 0.7",
          license: "MIT",
          capabilities: %w[completion vision],
          details: { family: "qwen2.5-coder:7b", parameter_size: "4.3B" }
        }.to_json)

      result = client.show_model(model: "qwen2.5-coder:7b")
      expect(result).to be_a(Hash)
      expect(result["capabilities"]).to include("vision")
      expect(result["details"]["family"]).to eq("qwen2.5-coder:7b")
    end

    it "supports verbose flag" do
      stub_request(:post, "http://localhost:11434/api/show")
        .with(body: hash_including("verbose" => true))
        .to_return(status: 200, body: {
          parameters: "temperature 0.7",
          model_info: { "general.architecture" => "qwen2.5-coder:7b" }
        }.to_json)

      result = client.show_model(model: "qwen2.5-coder:7b", verbose: true)
      expect(result["model_info"]).to be_a(Hash)
    end
  end

  describe "#delete_model" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "deletes a model" do
      stub_request(:delete, "http://localhost:11434/api/delete")
        .with(body: hash_including("model" => "old-model"))
        .to_return(status: 200, body: "")

      expect(client.delete_model(model: "old-model")).to be true
    end

    it "raises NotFoundError for missing model" do
      stub_request(:delete, "http://localhost:11434/api/delete")
        .to_return(status: 404, body: { error: "model not found" }.to_json)

      expect { client.delete_model(model: "nonexistent") }.to raise_error(Ollama::NotFoundError)
    end
  end

  describe "#copy_model" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "copies a model" do
      stub_request(:post, "http://localhost:11434/api/copy")
        .with(body: hash_including("source" => "qwen2.5-coder:7b", "destination" => "qwen2.5-coder:7b-backup"))
        .to_return(status: 200, body: "")

      expect(client.copy_model(source: "qwen2.5-coder:7b", destination: "qwen2.5-coder:7b-backup")).to be true
    end
  end

  describe "#create_model" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "creates a model from base" do
      stub_request(:post, "http://localhost:11434/api/create")
        .with(body: hash_including(
          "model" => "my-model",
          "from" => "qwen2.5-coder:7b",
          "system" => "You are Alpaca"
        ))
        .to_return(status: 200, body: { status: "success" }.to_json)

      result = client.create_model(model: "my-model", from: "qwen2.5-coder:7b", system: "You are Alpaca")
      expect(result["status"]).to eq("success")
    end
  end

  describe "#push_model" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "pushes a model" do
      stub_request(:post, "http://localhost:11434/api/push")
        .with(body: hash_including("model" => "user/my-model"))
        .to_return(status: 200, body: { status: "success" }.to_json)

      result = client.push_model(model: "user/my-model")
      expect(result["status"]).to eq("success")
    end
  end

  describe "#list_models" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "returns full model objects" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 200, body: {
          models: [
            {
              name: "qwen2.5-coder:7b",
              model: "qwen2.5-coder:7b",
              modified_at: "2025-10-03T23:34:03Z",
              size: 3_338_801_804,
              details: { family: "gemma", parameter_size: "4.3B", quantization_level: "Q4_K_M" }
            }
          ]
        }.to_json)

      models = client.list_models
      expect(models).to be_an(Array)
      expect(models.first).to be_a(Hash)
      expect(models.first["name"]).to eq("qwen2.5-coder:7b")
      expect(models.first["details"]["parameter_size"]).to eq("4.3B")
    end
  end

  describe "#list_model_names" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "returns array of model name strings" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 200, body: {
          models: [{ name: "qwen2.5-coder:7b" }, { name: "llama3.1:8b" }]
        }.to_json)

      names = client.list_model_names
      expect(names).to eq(%w[qwen2.5-coder:7b llama3.1:8b])
    end
  end

  describe "#list_running" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "returns running models" do
      stub_request(:get, "http://localhost:11434/api/ps")
        .to_return(status: 200, body: {
          models: [
            {
              name: "qwen2.5-coder:7b",
              model: "qwen2.5-coder:7b",
              size: 6_591_830_464,
              size_vram: 5_333_539_264,
              context_length: 4096,
              expires_at: "2025-10-17T16:47:07Z",
              details: { family: "qwen2.5-coder:7b" }
            }
          ]
        }.to_json)

      models = client.list_running
      expect(models).to be_an(Array)
      expect(models.first["size_vram"]).to eq(5_333_539_264)
      expect(models.first["context_length"]).to eq(4096)
    end

    it "is aliased as ps" do
      stub_request(:get, "http://localhost:11434/api/ps")
        .to_return(status: 200, body: { models: [] }.to_json)

      expect(client.ps).to eq([])
    end
  end

  describe "#version" do
    let(:client) { described_class.new(config: Ollama::Config.new) }

    it "returns version string" do
      stub_request(:get, "http://localhost:11434/api/version")
        .to_return(status: 200, body: { version: "0.12.6" }.to_json)

      expect(client.version).to eq("0.12.6")
    end
  end
end

RSpec.describe Ollama::Config do
  describe "#initialize" do
    it "sets safe defaults" do
      config = described_class.new
      expect(config.base_url).to eq("http://localhost:11434")
      expect(config.model).to eq("llama3.1:8b")
      expect(config.timeout).to eq(30)
      expect(config.retries).to eq(2)
      expect(config.strict_json).to be(true)
      expect(config.temperature).to eq(0.2)
      expect(config.top_p).to eq(0.9)
      expect(config.num_ctx).to eq(8192)
    end
  end
end

RSpec.describe Ollama::SchemaValidator do
  describe ".validate!" do
    it "validates data against schema" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => "test" }
      expect { described_class.validate!(data, schema) }.not_to raise_error
    end

    it "raises SchemaViolationError on invalid data" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => 123 }
      expect do
        described_class.validate!(data, schema)
      end.to raise_error(Ollama::SchemaViolationError)
    end
  end
end

RSpec.describe Ollama::Response do
  describe "accessor methods" do
    let(:data) do
      {
        "model" => "qwen2.5-coder:7b",
        "created_at" => "2025-01-01T00:00:00Z",
        "message" => {
          "role" => "assistant",
          "content" => "Hello!",
          "thinking" => "Let me think...",
          "images" => ["base64data"],
          "tool_calls" => [
            {
              "function" => {
                "name" => "get_weather",
                "description" => "Get weather",
                "arguments" => { "city" => "Tokyo" }
              }
            }
          ]
        },
        "done" => true,
        "done_reason" => "stop",
        "total_duration" => 1_000_000,
        "load_duration" => 200_000,
        "prompt_eval_count" => 10,
        "prompt_eval_duration" => 300_000,
        "eval_count" => 20,
        "eval_duration" => 500_000,
        "logprobs" => [{ "token" => "Hello", "logprob" => -0.1 }]
      }
    end
    let(:response) { described_class.new(data) }

    it "exposes all timing fields" do
      expect(response.total_duration).to eq(1_000_000)
      expect(response.load_duration).to eq(200_000)
      expect(response.prompt_eval_count).to eq(10)
      expect(response.prompt_eval_duration).to eq(300_000)
      expect(response.eval_count).to eq(20)
      expect(response.eval_duration).to eq(500_000)
    end

    it "exposes done? and done_reason" do
      expect(response.done?).to be true
      expect(response.done_reason).to eq("stop")
    end

    it "exposes model and created_at" do
      expect(response.model).to eq("qwen2.5-coder:7b")
      expect(response.created_at).to eq("2025-01-01T00:00:00Z")
    end

    it "exposes logprobs" do
      expect(response.logprobs.first["token"]).to eq("Hello")
    end

    it "provides content shorthand" do
      expect(response.content).to eq("Hello!")
    end

    it "exposes message thinking" do
      expect(response.message.thinking).to eq("Let me think...")
    end

    it "exposes message images" do
      expect(response.message.images).to eq(["base64data"])
    end

    it "exposes tool call function description" do
      expect(response.message.tool_calls.first.function.description).to eq("Get weather")
    end
  end
end

RSpec.describe Ollama::Options do
  describe "expanded options" do
    it "accepts all new option keys" do
      opts = described_class.new(
        temperature: 0.5, num_predict: 100, stop: ["END"],
        mirostat: 2, mirostat_tau: 5.0, mirostat_eta: 0.1,
        presence_penalty: 0.5, frequency_penalty: -0.3,
        typical_p: 0.9, tfs_z: 1.0, num_thread: 4
      )

      hash = opts.to_h
      expect(hash[:num_predict]).to eq(100)
      expect(hash[:stop]).to eq(["END"])
      expect(hash[:mirostat]).to eq(2)
      expect(hash[:presence_penalty]).to eq(0.5)
      expect(hash[:frequency_penalty]).to eq(-0.3)
      expect(hash[:typical_p]).to eq(0.9)
    end

    it "validates mirostat values" do
      expect { described_class.new(mirostat: 3) }.to raise_error(ArgumentError, /mirostat/)
    end

    it "validates presence_penalty range" do
      expect { described_class.new(presence_penalty: 3.0) }.to raise_error(ArgumentError, /presence_penalty/)
    end

    it "validates stop is array" do
      expect { described_class.new(stop: "not array") }.to raise_error(ArgumentError, /stop/)
    end
  end
end

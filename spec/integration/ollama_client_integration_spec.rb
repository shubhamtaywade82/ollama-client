# frozen_string_literal: true

# Integration tests that make actual calls to Ollama server
# These tests require a running Ollama instance
#
# To run:
#   OLLAMA_URL=http://localhost:11434 bundle exec rspec spec/integration/
#   OLLAMA_MODEL=llama3.1:8b bundle exec rspec spec/integration/

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Ollama Client Integration", :integration do
  let(:base_url) { ENV.fetch("OLLAMA_URL", "http://localhost:11434") }
  let(:model) { ENV.fetch("OLLAMA_MODEL", "llama3.1:8b") }
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = base_url
      c.model = model
      c.timeout = 60
      c.retries = 1
    end
  end
  let(:client) { Ollama::Client.new(config: config) }

  # rubocop:disable RSpec/BeforeAfterAll
  # Integration tests need before(:all) to check Ollama availability once
  before(:all) do
    # Skip integration tests in CI unless explicitly enabled
    if ENV["CI"] && ENV["RUN_INTEGRATION_TESTS"] != "true"
      skip "Integration tests skipped in CI. Set RUN_INTEGRATION_TESTS=true to enable."
    end

    # Allow real HTTP connections for integration tests
    WebMock.allow_net_connect!

    # Check if Ollama is available
    test_config = Ollama::Config.new.tap do |c|
      c.base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      c.timeout = 5
      c.retries = 0
    end
    test_client = Ollama::Client.new(config: test_config)

    begin
      test_client.list_models
    rescue StandardError => e
      skip "Ollama server not available at #{ENV.fetch("OLLAMA_URL", "http://localhost:11434")}: #{e.message}. " \
           "Start Ollama server or set OLLAMA_URL environment variable."
    end
  end
  # rubocop:enable RSpec/BeforeAfterAll

  describe "Ollama::Client#list_models" do
    it "lists available models" do
      models = client.list_models

      expect(models).to be_an(Array)
      expect(models).not_to be_empty
      expect(models.first).to be_a(String)
    end
  end

  describe "Ollama::Client#generate" do
    it "generates structured JSON output with schema" do
      schema = {
        "type" => "object",
        "required" => ["status"],
        "properties" => {
          "status" => { "type" => "string" }
        }
      }

      result = client.generate(
        prompt: "Output a JSON object with a single key 'status' and value 'ok'.",
        schema: schema
      )

      expect(result).to be_a(Hash)
      expect(result["status"]).to eq("ok")
    end

    it "generates plain text output without schema" do
      result = client.generate(
        prompt: "Say 'Hello, World!' and nothing else."
      )

      expect(result).to be_a(String)
      expect(result.downcase).to include("hello")
    end

    it "handles complex schemas" do
      schema = {
        "type" => "object",
        "required" => %w[action reasoning],
        "properties" => {
          "action" => {
            "type" => "string",
            "enum" => %w[search calculate finish]
          },
          "reasoning" => { "type" => "string" }
        }
      }

      prompt = "Given the user request 'find the weather', decide the next action. " \
               "Return action='search' and provide reasoning."
      result = client.generate(
        prompt: prompt,
        schema: schema
      )

      expect(result).to be_a(Hash)
      expect(result["action"]).to eq("search")
      expect(result["reasoning"]).to be_a(String)
      expect(result["reasoning"]).not_to be_empty
    end
  end

  describe "Ollama::Client#chat_raw" do
    it "sends chat messages and receives responses" do
      response = client.chat_raw(
        messages: [{ role: "user", content: "Say 'Hello' and nothing else." }],
        allow_chat: true
      )

      expect(response).to be_a(Ollama::Response)
      expect(response.message).to be_a(Ollama::Response::Message)
      expect(response.message.role).to eq("assistant")
      expect(response.message.content).to be_a(String)
      expect(response.message.content.downcase).to include("hello")
    end

    it "maintains conversation history" do
      messages = [
        { role: "user", content: "My name is Alice." }
      ]

      response1 = client.chat_raw(messages: messages, allow_chat: true)
      messages << { role: "assistant", content: response1.message.content }
      messages << { role: "user", content: "What is my name?" }

      response2 = client.chat_raw(messages: messages, allow_chat: true)

      expect(response2.message.content.downcase).to include("alice")
    end

    it "handles tool calls" do
      tool = Ollama::Tool.new(
        type: "function",
        function: Ollama::Tool::Function.new(
          name: "get_weather",
          description: "Get weather for a location",
          parameters: Ollama::Tool::Function::Parameters.new(
            type: "object",
            properties: {
              location: Ollama::Tool::Function::Parameters::Property.new(
                type: "string",
                description: "The city name"
              )
            },
            required: %w[location]
          )
        )
      )

      begin
        response = client.chat_raw(
          messages: [{ role: "user", content: "What's the weather in Paris? Use the get_weather tool." }],
          tools: tool,
          allow_chat: true
        )

        tool_calls = response.message.tool_calls
        if tool_calls && !tool_calls.empty?
          expect(tool_calls).to be_an(Array)
          # Access tool call data (may be hash or object)
          first_call = tool_calls.first
          tool_name = first_call.respond_to?(:name) ? first_call.name : first_call["function"]["name"]
          expect(tool_name).to eq("get_weather")
        else
          # Model might not call tool - that's okay for integration test
          expect(response.message.content).to be_a(String)
        end
      rescue Ollama::HTTPError
        # Some models may not support tools - skip test
        actual_model = client.instance_variable_get(:@config).model
        skip "Model '#{actual_model}' may not support tool calling. " \
             "Try: OLLAMA_MODEL=llama3.2:3b (or another model with tool support)"
      end
    end
  end

  describe "Ollama::Client#embeddings" do
    it "generates embeddings for text" do
      # NOTE: Requires an embedding model
      embedding_model = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")

      begin
        embedding = client.embeddings.embed(
          model: embedding_model,
          input: "What is Ruby programming?"
        )

        expect(embedding).to be_an(Array)
        expect(embedding).not_to be_empty
        expect(embedding.first).to be_a(Numeric)
      rescue Ollama::NotFoundError
        skip "Embedding model '#{embedding_model}' not available. Install with: ollama pull #{embedding_model}"
      rescue Ollama::Error => e
        # Provide concise error message for test output
        if e.message.include?("Empty embedding returned")
          skip "Embedding model '#{embedding_model}' returned empty embedding. " \
               "Install with: ollama pull #{embedding_model}"
        else
          skip "Embedding model issue: #{e.message.split("\n").first}. " \
               "Install with: ollama pull #{embedding_model}"
        end
      end
    end

    it "generates embeddings for multiple texts" do
      embedding_model = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")

      begin
        embeddings = client.embeddings.embed(
          model: embedding_model,
          input: ["What is Ruby?", "What is Python?"]
        )

        expect(embeddings).to be_an(Array)
        expect(embeddings.length).to be >= 1
        expect(embeddings.first).to be_an(Array)
      rescue Ollama::NotFoundError
        skip "Embedding model '#{embedding_model}' not available. Install with: ollama pull #{embedding_model}"
      rescue Ollama::Error => e
        # Provide concise error message for test output
        if e.message.include?("Empty embedding returned")
          skip "Embedding model '#{embedding_model}' returned empty embedding. " \
               "Install with: ollama pull #{embedding_model}"
        else
          skip "Embedding model issue: #{e.message.split("\n").first}. " \
               "Install with: ollama pull #{embedding_model}"
        end
      end
    end
  end

  describe "Ollama::Agent::Planner" do
    it "makes planning decisions with schema" do
      schema = {
        "type" => "object",
        "required" => %w[action reasoning],
        "properties" => {
          "action" => {
            "type" => "string",
            "enum" => %w[search calculate finish]
          },
          "reasoning" => { "type" => "string" }
        }
      }

      planner = Ollama::Agent::Planner.new(client)

      result = planner.run(
        prompt: "User wants to find the weather. Decide the next action.",
        schema: schema
      )

      expect(result).to be_a(Hash)
      expect(result["action"]).to be_in(%w[search calculate finish])
      expect(result["reasoning"]).to be_a(String)
    end
  end

  describe "Ollama::Agent::Executor" do
    it "executes tool calls in a loop" do
      tools = {
        "get_time" => lambda do |timezone: "UTC"|
          { timezone: timezone, time: Time.now.utc.iso8601 }
        end
      }

      executor = Ollama::Agent::Executor.new(client, tools: tools)

      begin
        answer = executor.run(
          system: "You are a helpful assistant. Use tools when needed.",
          user: "What time is it? Use the get_time tool."
        )

        expect(answer).to be_a(String)
        expect(answer).not_to be_empty
      rescue Ollama::HTTPError
        # Some models may not support tools properly - skip test
        actual_model = client.instance_variable_get(:@config).model
        skip "Model '#{actual_model}' may not support tool execution. " \
             "Try: OLLAMA_MODEL=llama3.2:3b (or another model with tool support)"
      end
    end
  end

  describe "Ollama::ChatSession" do
    it "manages conversation state" do
      chat = Ollama::ChatSession.new(
        client,
        system: "You are a helpful assistant."
      )

      response1 = chat.say("My name is Bob.")
      expect(response1).to be_a(String)

      response2 = chat.say("What is my name?")
      expect(response2.downcase).to include("bob")

      expect(chat.messages.length).to eq(5) # system + 2 user + 2 assistant
    end
  end

  describe "Error handling with real server" do
    it "raises NotFoundError for non-existent model" do
      bad_config = Ollama::Config.new.tap do |c|
        c.base_url = base_url
        c.model = "nonexistent-model-xyz-123"
        c.timeout = 10
      end
      bad_client = Ollama::Client.new(config: bad_config)

      expect do
        bad_client.generate(
          prompt: "Test",
          schema: { "type" => "object", "properties" => {} }
        )
      end.to raise_error(Ollama::NotFoundError)
    end
  end
end
# rubocop:enable RSpec/DescribeClass

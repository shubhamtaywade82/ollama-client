#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive live test script for ollama-client features.
# Run with: bundle exec ruby test_all_features.rb
# Requires Ollama running at localhost:11434.
# Override model: MODEL=llama3.2:3b bundle exec ruby test_all_features.rb

require "bundler/setup"
require "ollama_client"
require "json"

MODEL = ENV.fetch("MODEL", "qwen3.5:4b")
EMBED_MODEL = ENV.fetch("EMBED_MODEL", "nomic-embed-text")
COUNTS = { passed: 0, failed: 0 } # rubocop:disable Style/MutableConstant -- counters are mutated in place

def section(title)
  puts "\n#{"=" * 70}"
  puts "  #{title}"
  puts "=" * 70
end

def test(name)
  print "  #{name}... "
  $stdout.flush
  begin
    yield
    puts "\e[32m\u2713\e[0m PASS"
    COUNTS[:passed] += 1
  rescue StandardError => e
    puts "\e[31m\u2717\e[0m FAIL: #{e.message}"
    COUNTS[:failed] += 1
  end
end

def info(msg)
  puts "  \u21b3 #{msg}"
end

def assert(cond, msg = "assertion failed")
  raise msg unless cond
end

def assert_eq(actual, expected, msg = nil)
  raise msg || "expected #{actual.inspect} == #{expected.inspect}" unless actual == expected
end

def assert_kind(klass, obj)
  raise "expected #{obj.inspect} to be a #{klass}" unless obj.is_a?(klass)
end

def assert_not_empty(obj)
  raise "expected #{obj.inspect} to not be empty" if obj.nil? || (obj.respond_to?(:empty?) && obj.empty?)
end

def quick_client(timeout: 30)
  Ollama::Client.new(config: Ollama::Config.new.tap do |c|
    c.timeout = timeout
    c.retries = 0
  end)
end

section("CONFIGURATION")

test("Default config values") do
  c = Ollama::Config.new
  assert_eq "http://localhost:11434", c.base_url
  assert_eq 30, c.timeout
  assert_eq 2, c.retries
  assert_eq true, c.strict_json
  assert_eq 0.2, c.temperature
  assert_eq 0.9, c.top_p
  assert_eq 8192, c.num_ctx
end

test("Custom config") do
  c = Ollama::Config.new
  c.base_url = "http://custom:11434"
  c.model = "test-model"
  c.timeout = 60
  c.retries = 5
  c.temperature = 0.8
  c.top_p = 0.95
  c.num_ctx = 16_384
  c.strict_json = false
  assert_eq "http://custom:11434", c.base_url
  assert_eq "test-model", c.model
  assert_eq 60, c.timeout
  assert_eq false, c.strict_json
end

test("Per-client config isolation") do
  c1 = Ollama::Config.new.tap do |c|
    c.model = "model-a"
    c.temperature = 0.1
  end
  c2 = Ollama::Config.new.tap do |c|
    c.model = "model-b"
    c.temperature = 0.9
  end
  assert_eq "model-a", Ollama::Client.new(config: c1).config.model
  assert_eq "model-b", Ollama::Client.new(config: c2).config.model
  assert_eq 0.1, Ollama::Client.new(config: c1).config.temperature
end

test("Global config via Ollama.configure") do
  orig = Ollama.config.model
  Ollama.configure { _1.model = "global-test" }
  assert_eq "global-test", Ollama.config.model
  Ollama.configure { _1.model = orig }
end

section("BASIC GENERATE")

test("generate without schema returns String") do
  result = quick_client(timeout: 120).generate(prompt: "Say hello", model: MODEL)
  assert_kind String, result
  assert_not_empty result
  info "response: #{result[0..80]}"
end

test("generate with options override") do
  result = quick_client(timeout: 60).generate(prompt: "Hi", model: MODEL, options: { temperature: 0.9, top_p: 0.95 })
  assert_not_empty result
end

test("generate with system prompt") do
  result = quick_client.generate(prompt: "Reply with just the word: OK", system: "You are terse.", model: MODEL)
  assert_not_empty result
  info "response: #{result[0..60]}"
end

test("generate with return_meta") do
  result = quick_client.generate(prompt: "Count to 3", model: MODEL, return_meta: true)
  assert_kind Hash, result
  assert result.key?("data")
  assert result.key?("meta")
  info "meta: #{result["meta"]}"
end

test("generate streaming hooks") do
  tokens = []
  result = quick_client(timeout: 10).generate(prompt: "Count 1 2 3", model: MODEL, hooks: {
                                                on_token: ->(t) { tokens << t },
                                                on_complete: -> {}
                                              })
  assert_not_empty result
  info "received #{tokens.size} token callbacks"
end

section("CHAT")

test("basic chat") do
  response = quick_client.chat(messages: [{ role: "user", content: "Say hello" }], model: MODEL)
  assert_kind Ollama::Response, response
  assert_not_empty response.content
  assert_eq "assistant", response.message.role
  info "response: #{response.content[0..80]}"
end

test("chat with keep_alive") do
  response = quick_client.chat(messages: [{ role: "user", content: "Hi" }], model: MODEL, keep_alive: "5m")
  assert_not_empty response.content
end

test("chat streaming via hooks") do
  tokens = []
  response = quick_client(timeout: 60).chat(
    messages: [{ role: "user", content: "Say: hello world" }],
    model: MODEL,
    hooks: { on_token: ->(t, *) { tokens << t }, on_complete: -> {} }
  )
  assert_not_empty response.content
  info "hook tokens: #{tokens.size}, content: #{response.content[0..40]}"
end

section("EMBEDDINGS")

test("single embedding") do
  result = quick_client(timeout: 30).embeddings.embed(model: EMBED_MODEL, input: "Hello world")
  assert_kind Array, result
  assert result.size.positive?
  assert_kind Float, result.first
  info "dimension: #{result.size}"
end

test("batch embedding") do
  result = quick_client(timeout: 30).embeddings.embed(model: EMBED_MODEL, input: %w[Hello World])
  assert_kind Array, result
  assert_eq 2, result.size
  assert_kind Array, result.first
  info "batch size: #{result.size}, dim: #{result.first.size}"
end

section("MODEL MANAGEMENT")

test("list models") do
  models = quick_client.list_models
  assert_kind Array, models
  info "found #{models.size} models"
end

test("list model names") do
  names = quick_client.list_model_names
  assert_kind Array, names
  assert names.size.positive?
  info "names: #{names.first(5)}"
end

test("list running models") do
  running = quick_client.list_running
  assert_kind Array, running
  info "#{running.size} running"
end

test("show model details") do
  details = quick_client.show_model(model: MODEL)
  assert_kind Hash, details
  assert_not_empty details
  info "keys: #{details.keys.first(6)}"
end

test("get server version") do
  version = quick_client.version
  assert_kind String, version
  info version
end

section("TOOLS & SCHEMA DSL")

test("Tool DSL produces valid tool hash") do
  weather = Class.new(Ollama::ToolDSL) do
    description "Get weather for a city"
    tool_name "get_weather"
    input do
      string :city, description: "City name"
      string :unit, optional: true, default: "celsius", enum: %w[celsius fahrenheit]
    end
    call { {}.freeze }
  end
  hash = weather.to_tool_hash
  assert_eq "get_weather", hash.dig("function", "name")
  assert_eq "celsius", hash.dig("function", "parameters", "properties", "unit", "default")
  info "tool: #{hash.dig("function", "name")}, params: #{hash.dig("function", "parameters", "properties").keys.join(", ")}"
end

test("Schema DSL produces valid schema") do
  schema = Ollama::SchemaDSL.define do
    string :color, enum: %w[red green blue]
    number :price, minimum: 0, maximum: 999
    boolean :available, optional: true
  end.to_h
  assert_eq "object", schema["type"]
  assert_eq %w[color price], schema["required"]
  assert_eq %w[red green blue], schema["properties"]["color"]["enum"]
  info "schema: type=#{schema["type"]}, required=#{schema["required"]}"
end

section("PROFILES & SANITIZER")

test("model profile") do
  p = Ollama::Client.new.profile(MODEL)
  assert_kind Ollama::ModelProfile, p
  info "profile loaded for #{MODEL}"
end

test("history sanitizer") do
  s = Ollama::Client.new.history_sanitizer(MODEL)
  assert_kind Ollama::HistorySanitizer, s
  # Build a minimal response-like object carrying thinking + content
  response = Struct.new(:content, :message, :model) do
    def to_s = content
  end.new(
    "Hello",
    Struct.new(:thinking).new("working through it..."),
    MODEL
  )

  messages = []
  appended = s.add(response, messages: messages)
  assert_kind Hash, appended
  assert_eq "Hello", appended[:content]
  assert_eq 1, messages.size
  assert_eq "Hello", messages[0][:content]
  info "sanitized #{messages.size} messages"
end

section("RAW ADAPTER")

test("raw GET /api/tags") do
  result = quick_client.raw.get("/api/tags")
  assert_kind Hash, result
  assert result.key?("models")
  info "found #{result["models"].size} models"
end

section("ERROR HIERARCHY")

test("all error classes inherit from Ollama::Error") do
  assert Ollama::TimeoutError < Ollama::Error
  assert Ollama::InvalidJSONError < Ollama::Error
  assert Ollama::SchemaViolationError < Ollama::Error
  assert Ollama::RetryExhaustedError < Ollama::Error
  assert Ollama::HTTPError < Ollama::Error
  assert Ollama::NotFoundError < Ollama::Error
  assert Ollama::StreamError < Ollama::Error
  assert Ollama::UnsupportedThinkingModel < Ollama::Error
  info "8 error classes verified"
end

total = COUNTS[:passed] + COUNTS[:failed]
puts "\n#{"=" * 70}"
puts "  RESULTS: #{COUNTS[:passed]}/#{total} passed, #{COUNTS[:failed]} failed"
puts "=" * 70
exit(COUNTS[:failed].positive? ? 1 : 0)

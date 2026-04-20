#!/usr/bin/env ruby
# frozen_string_literal: true

# Live smoke checks for this branch (model profiles, chat extensions,
# GenerateStreamHandler path via generate hooks, JsonFragmentExtractor, etc.).
#
# Usage (from repo root):
#   bundle exec ruby script/live_branch_smoke.rb
#
# Environment:
#   OLLAMA_BASE_URL   — default http://localhost:11434
#   OLLAMA_MODEL      — primary text model (default: llama3.2:3b)
#   OLLAMA_API_KEY    — optional Bearer token (Ollama Cloud)
#   OLLAMA_GEMMA_MODEL — optional; if set, runs Gemma-specific profile / think-tag checks
#   OLLAMA_EMBED_MODEL — optional; default nomic-embed-text:latest when present in tags
#
# Requires a running Ollama with the chosen model(s) pulled.

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib")) unless $LOAD_PATH.include?(File.join(ROOT, "lib"))

require "bundler/setup"
require "json"
require "ollama_client"

# Live HTTP checks for models, chat, generate, embeddings, and branch-only APIs.
class LiveBranchSmoke
  def initialize
    @base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    @model = ENV.fetch("OLLAMA_MODEL", "llama3.2:3b")
    @gemma_model = ENV.fetch("OLLAMA_GEMMA_MODEL", nil)
    @embed_model = ENV.fetch("OLLAMA_EMBED_MODEL", nil)
    @passed = 0
    @skipped = 0
    @failed = 0
  end

  def run
    banner("ollama-client live smoke (#{Ollama::VERSION})")
    puts "Base URL: #{@base_url}"
    puts "Primary model: #{@model}"
    puts

    client = build_client
    return abort_no_server(client) unless server_up?(client)

    run_safe("list_models") { exercise_list_models(client) }
    run_safe("version") { exercise_version(client) }
    run_safe("model_profile") { exercise_model_profile }
    run_safe("client.profile") { exercise_client_profile(client) }
    run_safe("capabilities.for") { exercise_capabilities(client) }
    run_safe("json_fragment_extractor") { exercise_json_fragment_extractor }
    run_safe("generate_plain") { exercise_generate_plain(client) }
    run_safe("generate_schema") { exercise_generate_schema(client) }
    run_safe("generate_stream_hooks") { exercise_generate_stream(client) }
    run_safe("chat_plain") { exercise_chat_plain(client) }
    run_safe("chat_profile_auto") { exercise_chat_profile_auto(client) }
    run_safe("chat_stream_hooks") { exercise_chat_stream_hooks(client) }
    run_safe("multimodal_input_text_only") { exercise_multimodal_text_only }
    run_safe("history_sanitizer") { exercise_history_sanitizer(client) }
    run_safe("stream_event") { exercise_stream_event }
    run_safe("embeddings") { exercise_embeddings(client) }
    run_safe("gemma_profile") { exercise_gemma_optional(client) }

    summary
    @failed.zero? ? 0 : 1
  end

  private

  def banner(title)
    width = 60
    puts "=" * width
    puts title.center(width)
    puts "=" * width
  end

  def build_client
    cfg = Ollama::Config.new
    cfg.base_url = @base_url
    cfg.model = @model
    cfg.timeout = 120
    key = ENV.fetch("OLLAMA_API_KEY", nil)
    cfg.api_key = key if key && !key.strip.empty?
    Ollama::Client.new(config: cfg)
  end

  def server_up?(client)
    client.list_models
    true
  rescue StandardError => e
    warn "Server check failed: #{e.class}: #{e.message}"
    false
  end

  def abort_no_server(_client)
    warn "\nStart Ollama (e.g. `ollama serve`) and pull a model, then re-run."
    1
  end

  def run_safe(label)
    print "[#{label}] "
    yield
    puts "PASS"
    @passed += 1
  rescue StandardError => e
    if e.message.match?(/skip|not available|unsupported/i)
      puts "SKIP (#{e.message})"
      @skipped += 1
    else
      puts "FAIL: #{e.class}: #{e.message}"
      @failed += 1
    end
  end

  def exercise_list_models(client)
    models = client.list_models
    raise "expected non-empty model list" if models.nil? || models.empty?

    puts "#{models.size} models — "
  end

  def exercise_version(client)
    v = client.version
    raise "empty version" if v.to_s.strip.empty?

    print "version=#{v.inspect} — "
  end

  def exercise_model_profile
    p = Ollama::ModelProfile.for(@model)
    raise "missing family" if p.family.nil?

    print "family=#{p.family} thinking=#{p.thinking?} — "
  end

  def exercise_client_profile(client)
    p = client.profile(@model)
    raise "wrong class" unless p.is_a?(Ollama::ModelProfile)

    print "same family=#{p.family} — "
  end

  def exercise_capabilities(client)
    models = client.list_models
    entry = models.find { |m| (m["name"] || "").start_with?(@model.split(":").first) }
    entry ||= models.first
    raise "no model entry for capabilities" unless entry

    caps = entry["capabilities"] || Ollama::Capabilities.for(entry)
    raise "caps not hash" unless caps.is_a?(Hash)

    print caps.inspect, " — "
  end

  def exercise_json_fragment_extractor
    text = 'Here is JSON: {"ok":true,"n":2} trailing'
    raw = Ollama::JsonFragmentExtractor.call(text)
    out = JSON.parse(raw)
    raise "fragment mismatch" unless out == { "ok" => true, "n" => 2 }

    print "fragment=#{raw[0, 20]}... — "
  end

  def exercise_generate_plain(client)
    out = client.generate(prompt: "Reply with exactly: LIVE_OK", model: @model, strict: false)
    raise "not string" unless out.is_a?(String)

    print "chars=#{out.size} — "
  end

  def exercise_generate_schema(client)
    schema = {
      "type" => "object",
      "required" => ["live"],
      "properties" => { "live" => { "type" => "boolean" } }
    }
    out = client.generate(
      prompt: 'Return JSON only: {"live": true}',
      schema: schema,
      model: @model
    )
    raise "not hash" unless out.is_a?(Hash)
    raise "live not true" unless out["live"] == true

    print "structured ok — "
  end

  def exercise_generate_stream(client)
    tokens = []
    client.generate(
      prompt: "Say the single digit 7 once, nothing else.",
      model: @model,
      hooks: { on_token: ->(t) { tokens << t } }
    )
    raise "no tokens" if tokens.empty?

    print "token_chunks=#{tokens.size} — "
  end

  def exercise_chat_plain(client)
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Reply with exactly: CHAT_OK" }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    body = r.content.to_s
    raise "empty content" if body.strip.empty?

    print "content_len=#{body.size} — "
  end

  def exercise_chat_profile_auto(client)
    r = client.chat(
      model: @model,
      profile: :auto,
      messages: [{ role: "user", content: "Say hi in one word." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    print "usage=#{r.usage.inspect} — "
  end

  def exercise_chat_stream_hooks(client)
    tokens = []
    thoughts = []
    client.chat(
      model: @model,
      messages: [{ role: "user", content: "Count 1 then 2 only." }],
      hooks: {
        on_token: ->(t) { tokens << t },
        on_thought: ->(evt) { thoughts << evt }
      }
    )
    raise "no answer tokens" if tokens.join.strip.empty?

    print "tokens=#{tokens.size} thought_events=#{thoughts.size} — "
  end

  def exercise_multimodal_text_only
    profile = Ollama::ModelProfile.for(@model)
    input = Ollama::MultimodalInput.build(
      [
        { type: :text, data: "Part A." },
        { type: :text, data: "Part B." }
      ],
      profile: profile
    )
    msg = input.to_message
    raise "bad role" unless msg[:role].to_s == "user"

    print "content includes both parts=#{msg[:content].include?("Part")} — "
  end

  def exercise_history_sanitizer(client)
    messages = [{ role: "user", content: "Say OK for history test." }]
    r = client.chat(model: @model, messages: messages)
    san = client.history_sanitizer(@model)
    san.add(r, messages: messages)
    last = messages.last
    raise "assistant missing" unless last[:role] == "assistant"

    print "messages=#{messages.size} — "
  end

  def exercise_stream_event
    e = Ollama::StreamEvent.new(type: :thought_delta, data: "x", model: @model)
    line = e.to_jsonl
    parsed = JSON.parse(line)
    raise "bad jsonl" unless parsed["type"] == "thought_delta"

    print "jsonl ok — "
  end

  def exercise_embeddings(client)
    embed_name = @embed_model || pick_embedding_model(client)
    raise "skip: no embedding model in tags (set OLLAMA_EMBED_MODEL)" unless embed_name

    vec = client.embeddings.embed(model: embed_name, input: "live smoke")
    raise "not vector" unless vec.is_a?(Array) && vec.first.is_a?(Numeric)

    print "model=#{embed_name} dim=#{vec.size} — "
  end

  def exercise_gemma_optional(client)
    raise "skip: set OLLAMA_GEMMA_MODEL to run Gemma profile / think-tag checks" unless @gemma_model

    model = @gemma_model
    r = client.chat(
      model: model,
      think: true,
      messages: [
        { role: "system", content: "You are brief." },
        { role: "user", content: "Say pong." }
      ]
    )
    raise "no content" if r.content.to_s.strip.empty?

    print "gemma chat ok len=#{r.content.size} — "
  end

  def pick_embedding_model(client)
    names = client.list_models.map { |m| m["name"].to_s }
    %w[nomic-embed-text:latest mxbai-embed-large:latest].find { |n| names.include?(n) }
  end

  def summary
    puts
    banner("Summary")
    puts "PASS:   #{@passed}"
    puts "SKIP:   #{@skipped}"
    puts "FAIL:   #{@failed}"
    puts(@failed.zero? ? "\nAll executed checks completed without failures." : "\nSome checks failed.")
  end
end

exit LiveBranchSmoke.new.run if $PROGRAM_NAME == __FILE__

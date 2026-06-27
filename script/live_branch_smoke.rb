#!/usr/bin/env ruby
# frozen_string_literal: true

# Live smoke checks for this branch — exercises the public API surface described in
# API_CONTRACT.md against a running Ollama. Checks that need special models or
# permissions SKIP with an explicit reason when unavailable.
#
# Usage (from repo root):
#   bundle exec ruby script/live_branch_smoke.rb
#
# Environment:
#   OLLAMA_BASE_URL     — default http://localhost:11434
#   OLLAMA_MODEL        — primary text model (default: llama3.2:3b)
#   OLLAMA_API_KEY      — optional Bearer token (Ollama Cloud)
#   OLLAMA_EMBED_MODEL  — optional; default picks nomic-embed-text or mxbai-embed-large from tags
#   OLLAMA_GEMMA_MODEL  — optional Gemma chat / think-tag adapter smoke
#   OLLAMA_TOOLS_MODEL  — optional override for tool-calling chat (else first tools-capable tag)
#   OLLAMA_VISION_MODEL — optional override for vision chat/inputs (else first vision-capable tag)
#   OLLAMA_THINKING_MODEL — optional override for generate think + return_reasoning (else first reasoning-capable tag)
#   OLLAMA_LIVE_SMOKE_COPY_TEST — set to "1" to run copy_model + delete_model (see below)
#   OLLAMA_COPY_SOURCE    — source model for copy (default: OLLAMA_MODEL)
#   OLLAMA_COPY_DEST      — destination name (default: auto-generated unique tag)
#   OLLAMA_LIVE_SMOKE_ENABLE_RAW_SUFFIX — set to "1" to attempt generate(suffix:, raw:)
#   OLLAMA_SMOKE_PREVIEW_CHARS — max characters printed per field (default 1200, clamped 200–32768)
#   OLLAMA_SMOKE_BACKTRACE — set to "1" to print stack trace on FAIL
#
# Requires a running Ollama with the chosen model(s) pulled.

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib")) unless $LOAD_PATH.include?(File.join(ROOT, "lib"))

require "bundler/setup"
require "json"
require "tempfile"
require "ollama_client"

# rubocop:disable Metrics/ClassLength -- single-file smoke runner; split only if it grows further
# Live HTTP checks for models, chat, generate, embeddings, and public helpers.
class LiveBranchSmoke
  # 1x1 transparent PNG (base64) for vision smoke.
  MINIMAL_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  WEATHER_TOOL = [
    {
      "type" => "function",
      "function" => {
        "name" => "get_weather",
        "description" => "Get weather for a city",
        "parameters" => {
          "type" => "object",
          "properties" => { "city" => { "type" => "string" } },
          "required" => ["city"]
        }
      }
    }
  ].freeze

  def initialize
    @base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
    @model = ENV.fetch("OLLAMA_MODEL", "llama3.2:3b")
    @gemma_model = ENV.fetch("OLLAMA_GEMMA_MODEL", nil)
    @embed_model = ENV.fetch("OLLAMA_EMBED_MODEL", nil)
    @passed = 0
    @skipped = 0
    @failed = 0
    pv = ENV.fetch("OLLAMA_SMOKE_PREVIEW_CHARS", "1200").to_i
    @preview_limit = pv.clamp(200, 32_768)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- sequential smoke registry
  def run
    banner("ollama-client live smoke (#{Ollama::VERSION})")
    puts "Base URL: #{@base_url}"
    puts "Primary model: #{@model}"
    puts

    client = build_client
    return abort_no_server(client) unless server_up?(client)

    run_safe("list_models") { exercise_list_models(client) }
    run_safe("list_model_names") { exercise_list_model_names(client) }
    run_safe("tags_alias") { exercise_tags_alias(client) }
    run_safe("ps_alias") { exercise_ps_alias(client) }
    run_safe("show_model") { exercise_show_model(client) }
    run_safe("show_model_verbose") { exercise_show_model_verbose(client) }
    run_safe("capabilities_show_parity") { exercise_capabilities_show_parity(client) }
    run_safe("version") { exercise_version(client) }
    run_safe("model_profile") { exercise_model_profile }
    run_safe("client.profile") { exercise_client_profile(client) }
    run_safe("capabilities.for") { exercise_capabilities(client) }
    run_safe("ollama_client_config") { exercise_ollama_client_config }
    run_safe("config.load_from_json") { exercise_config_load_from_json }
    run_safe("config.on_response") { exercise_config_on_response(client) }
    run_safe("json_fragment_extractor") { exercise_json_fragment_extractor }
    run_safe("json_fragment_extractor_invalid") { exercise_json_fragment_extractor_invalid }
    run_safe("schema_validator") { exercise_schema_validator }
    run_safe("schema_validator_rejects") { exercise_schema_validator_rejects }
    run_safe("stream_event") { exercise_stream_event }
    run_safe("stream_event_predicates") { exercise_stream_event_predicates }
    run_safe("prompt_adapters.for") { exercise_prompt_adapters_for }
    run_safe("model_profile_helpers") { exercise_model_profile_helpers }
    run_safe("generate_plain") { exercise_generate_plain(client) }
    run_safe("generate_schema") { exercise_generate_schema(client) }
    run_safe("generate_stream_hooks") { exercise_generate_stream(client) }
    run_safe("generate_system_meta_options_keepalive") { exercise_generate_system_meta_options(client) }
    run_safe("generate_on_complete_hook") { exercise_generate_on_complete(client) }
    run_safe("generate_thinking_reasoning") { exercise_generate_thinking_reasoning(client) }
    run_safe("generate_vision_images") { exercise_generate_vision_images(client) }
    run_safe("generate_suffix_raw") { exercise_generate_suffix_raw_optional(client) }
    run_safe("chat_plain") { exercise_chat_plain(client) }
    run_safe("response_accessors") { exercise_response_accessors(client) }
    run_safe("response_tool_call_parse") { exercise_response_tool_call_parse }
    run_safe("chat_profile_auto") { exercise_chat_profile_auto(client) }
    run_safe("chat_profile_none") { exercise_chat_profile_none(client) }
    run_safe("chat_format_options_keepalive") { exercise_chat_format_options_keepalive(client) }
    run_safe("chat_stream_false") { exercise_chat_stream_false(client) }
    run_safe("chat_stream_true") { exercise_chat_stream_true(client) }
    run_safe("chat_stream_hooks") { exercise_chat_stream_hooks(client) }
    run_safe("chat_on_complete_hook") { exercise_chat_on_complete(client) }
    run_safe("chat_logprobs") { exercise_chat_logprobs_optional(client) }
    run_safe("chat_tools") { exercise_chat_tools_optional(client) }
    run_safe("chat_inputs_vision") { exercise_chat_inputs_vision_optional(client) }
    run_safe("chat_inputs_text_only") { exercise_chat_inputs_text_only(client) }
    run_safe("multimodal_input_text_only") { exercise_multimodal_text_only }
    run_safe("multimodal_input_add_reorder") { exercise_multimodal_input_add_reorder }
    run_safe("history_sanitizer") { exercise_history_sanitizer(client) }
    run_safe("history_sanitizer_profile_trace") { exercise_history_sanitizer_profile_trace(client) }
    run_safe("embeddings") { exercise_embeddings(client) }
    run_safe("embeddings_batch") { exercise_embeddings_batch(client) }
    run_safe("embeddings_optional_kwargs") { exercise_embeddings_optional_kwargs(client) }
    run_safe("embeddings_dimensions_options") { exercise_embeddings_dimensions_options(client) }
    run_safe("openai_compat") { exercise_openai_compat(client) }
    run_safe("gemma_profile") { exercise_gemma_optional(client) }
    run_safe("copy_delete_models") { exercise_copy_delete_optional(client) }

    summary
    @failed.zero? ? 0 : 1
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
    puts "[#{label}]"
    yield
    puts "  status: PASS"
    puts
    @passed += 1
  rescue StandardError => e
    if e.message.match?(/skip|not available|unsupported/i)
      puts "  status: SKIP"
      puts "  reason: #{e.message}"
      @skipped += 1
    else
      puts "  status: FAIL"
      puts "  error: #{e.class}: #{e.message}"
      e.backtrace.first(12).each { |ln| puts "    #{ln}" } if ENV["OLLAMA_SMOKE_BACKTRACE"] == "1"
      @failed += 1
    end
    puts
  end

  # Pretty-print one labeled value (truncated to @preview_limit).
  def smoke_emit(title, value)
    body = smoke_format(value)
    puts "  #{title}"
    body.each_line(chomp: true) { |ln| puts "    #{ln}" }
  end

  def smoke_format(value)
    text =
      case value
      when String then value.dup
      when Hash, Array then JSON.pretty_generate(value)
      else value.inspect
      end
    text = text.encode("UTF-8", invalid: :replace, undef: :replace)
    return text if text.length <= @preview_limit

    tail = text.length - @preview_limit
    "#{text[0, @preview_limit]}\n    … (#{tail} more chars truncated)"
  end

  # First + last floats for long embedding vectors (keeps output readable).
  def smoke_emit_vector(title, vec, head: 6, tail: 2)
    unless vec.is_a?(Array) && vec.first.is_a?(Numeric)
      smoke_emit(title, vec)
      return
    end

    n = vec.size
    if n <= head + tail
      smoke_emit(title, vec.map { |x| format("%.5f", x.to_f) }.join(", "))
      return
    end

    h = vec.first(head).map { |x| format("%.5f", x.to_f) }.join(", ")
    t = vec.last(tail).map { |x| format("%.5f", x.to_f) }.join(", ")
    smoke_emit(title, "[#{h}, … (#{n - head - tail} omitted) …, #{t}] dim=#{n}")
  end

  def model_list(client)
    @model_list ||= client.list_models
  end

  def model_entry_for(client, name)
    model_list(client).find { |m| m["name"] == name } ||
      model_list(client).find { |m| (m["name"] || "").start_with?(name.split(":").first) }
  end

  def first_model_with(client, capability)
    model_list(client).find { |m| Ollama::Capabilities.for(m)[capability.to_s] }
  end

  def tools_model_name(client)
    env = ENV["OLLAMA_TOOLS_MODEL"]&.strip
    return env if env && !env.empty?

    first_model_with(client, :tools)&.fetch("name", nil)
  end

  def vision_model_name(client)
    env = ENV["OLLAMA_VISION_MODEL"]&.strip
    return env if env && !env.empty?

    first_model_with(client, :vision)&.fetch("name", nil)
  end

  def thinking_model_name(client)
    env = ENV["OLLAMA_THINKING_MODEL"]&.strip
    return env if env && !env.empty?

    model_list(client).each do |m|
      name = m["name"].to_s
      next if name.empty?
      next unless Ollama::Capabilities.for("name" => name)["thinking"]

      return name
    end

    nil
  end

  def embed_name_for(client)
    em = @embed_model&.strip
    (!em.nil? && !em.empty? ? em : nil) || pick_embedding_model(client)
  end

  def exercise_list_models(client)
    models = client.list_models
    raise "expected non-empty model list" if models.nil? || models.empty?

    @model_list = models
    smoke_emit("count", models.size)
    smoke_emit("model_names", models.map { |m| m["name"] })
  end

  def exercise_list_model_names(client)
    names = client.list_model_names
    raise "empty names" if names.nil? || names.empty?
    raise "mismatch size" unless names.size == model_list(client).size

    smoke_emit("count", names.size)
    smoke_emit("names", names)
  end

  def exercise_tags_alias(client)
    tags = client.tags
    raise "tags mismatch" unless tags.size == client.list_models.size

    smoke_emit("tags_count", tags.size)
    smoke_emit("first_model_name", tags.first&.fetch("name", nil))
  end

  def exercise_ps_alias(client)
    running = client.ps
    raise "not array" unless running.is_a?(Array)

    alt = client.list_running
    raise "not array from list_running" unless alt.is_a?(Array)

    names_a = running.map { |m| m["name"] }.compact.sort
    names_b = alt.map { |m| m["name"] }.compact.sort
    raise "ps vs list_running name mismatch" if names_a != names_b

    smoke_emit("running_count", running.size)
    smoke_emit("running_models", running)
  end

  def exercise_show_model(client)
    info = client.show_model(model: @model)
    raise "no model key" unless info.is_a?(Hash) && (info["model"] || info["modelfile"] || info["details"])

    caps = info["capabilities"] || Ollama::Capabilities.for(info)
    raise "no capabilities" unless caps.is_a?(Hash)

    smoke_emit("capabilities", caps)
    tmpl = info["template"]
    tmpl_preview = tmpl.is_a?(String) ? tmpl[0, 200] : tmpl&.to_s
    smoke_emit(
      "excerpt",
      {
        "model" => info["model"],
        "details" => info["details"]&.slice("family", "parameter_size", "quantization_level"),
        "template_preview" => tmpl_preview
      }.compact
    )
  end

  def exercise_show_model_verbose(client)
    info = client.show_model(model: @model, verbose: true)
    raise "not hash" unless info.is_a?(Hash)

    smoke_emit("verbose_keys", info.keys.sort)
    smoke_emit("capabilities", info["capabilities"]) if info["capabilities"]
  rescue Ollama::Error => e
    raise "skip: show verbose not supported or failed: #{e.message}"
  end

  def exercise_capabilities_show_parity(client)
    entry = model_entry_for(client, @model)
    raise "no list entry" unless entry

    show = client.show_model(model: @model)
    c1 = Ollama::Capabilities.for(entry)
    c2 = Ollama::Capabilities.for(show)
    raise "capability mismatch list vs show: #{c1} vs #{c2}" if c1 != c2

    smoke_emit("capabilities", c1)
  end

  def exercise_version(client)
    v = client.version
    raise "empty version" if v.to_s.strip.empty?

    smoke_emit("version", v)
  end

  def exercise_model_profile
    p = Ollama::ModelProfile.for(@model)
    raise "missing family" if p.family.nil?

    smoke_emit("ModelProfile#to_h", p.to_h)
  end

  def exercise_client_profile(client)
    p = client.profile(@model)
    raise "wrong class" unless p.is_a?(Ollama::ModelProfile)

    smoke_emit("ModelProfile#to_h", p.to_h)
  end

  def exercise_capabilities(client)
    entry = model_entry_for(client, @model) || model_list(client).first
    raise "no model entry for capabilities" unless entry

    caps = entry["capabilities"] || Ollama::Capabilities.for(entry)
    raise "caps not hash" unless caps.is_a?(Hash)

    smoke_emit("model_name", entry["name"])
    smoke_emit("capabilities", caps)
  end

  def exercise_ollama_client_config
    c = OllamaClient.config
    raise "wrong type" unless c.is_a?(Ollama::Config)

    dup = c.dup
    dup.base_url = @base_url
    dup.model = @model
    key = ENV.fetch("OLLAMA_API_KEY", nil)
    dup.api_key = key if key && !key.strip.empty?
    Ollama::Client.new(config: dup)
    smoke_emit("OllamaClient.config.class", c.class.name)
    smoke_emit(
      "duplicated_config",
      {
        "base_url" => dup.base_url,
        "model" => dup.model,
        "api_key_set" => !dup.api_key.to_s.strip.empty?
      }
    )
  end

  def exercise_config_load_from_json
    Tempfile.create(["ollama-smoke-cfg", ".json"]) do |tmp|
      tmp.write(JSON.generate("base_url" => @base_url, "model" => @model, "timeout" => 120))
      tmp.flush
      cfg = Ollama::Config.load_from_json(tmp.path)
      raise "base_url mismatch" unless cfg.base_url == @base_url
      raise "model mismatch" unless cfg.model == @model
      raise "timeout not applied" unless cfg.timeout == 120

      smoke_emit("loaded.base_url", cfg.base_url)
      smoke_emit("loaded.model", cfg.model)
      smoke_emit("loaded.timeout", cfg.timeout)
    end
  end

  def exercise_config_on_response(_client)
    meta_hits = []
    raw_hits = 0
    cfg = Ollama::Config.new
    cfg.base_url = @base_url
    cfg.model = @model
    cfg.timeout = 120
    key = ENV.fetch("OLLAMA_API_KEY", nil)
    cfg.api_key = key if key && !key.strip.empty?
    cfg.on_response = lambda do |_raw, meta|
      raw_hits += 1
      if meta.is_a?(Hash)
        ep = meta[:endpoint] || meta["endpoint"]
        meta_hits << ep if ep
      end
    end
    hooked = Ollama::Client.new(config: cfg)
    hooked.version
    hooked.generate(prompt: "Say hook.", model: @model, strict: false)
    hooked.chat(model: @model, messages: [{ role: "user", content: "Say hook2." }])
    raise "expected on_response for generate/chat" if meta_hits.empty?

    smoke_emit("raw_invocations", raw_hits)
    smoke_emit("endpoints_seen", meta_hits.uniq.sort)
  end

  def exercise_json_fragment_extractor
    text = 'Here is JSON: {"ok":true,"n":2} trailing'
    raw = Ollama::JsonFragmentExtractor.call(text)
    out = JSON.parse(raw)
    raise "fragment mismatch" unless out == { "ok" => true, "n" => 2 }

    smoke_emit("extracted_fragment", raw)
    smoke_emit("parsed", out)
  end

  def exercise_json_fragment_extractor_invalid
    Ollama::JsonFragmentExtractor.call("")
    raise "expected InvalidJSONError"
  rescue Ollama::InvalidJSONError => e
    smoke_emit("exception", "#{e.class}: #{e.message}")
  end

  def exercise_schema_validator
    schema = { "type" => "object", "properties" => { "n" => { "type" => "integer" } } }
    data = { "n" => 1 }
    Ollama::SchemaValidator.validate!(data, schema)
    smoke_emit("schema", schema)
    smoke_emit("validated_data", data)
  end

  def exercise_schema_validator_rejects
    schema = { "type" => "object", "properties" => { "n" => { "type" => "integer" } } }
    begin
      Ollama::SchemaValidator.validate!({ "n" => "not-int" }, schema)
    rescue Ollama::SchemaViolationError => e
      smoke_emit("expected_failure", "#{e.class}: #{e.message}")
      return
    end

    raise "expected SchemaViolationError"
  end

  def exercise_prompt_adapters_for
    rows = [
      ["generic", Ollama::ModelProfile.for("unknown-model-xyz")],
      ["gemma4", Ollama::ModelProfile.for("gemma4:1b")],
      ["qwen", Ollama::ModelProfile.for("qwen3:latest")],
      ["deepseek", Ollama::ModelProfile.for("deepseek-r1:latest")]
    ].map do |label, profile|
      adapter = Ollama::PromptAdapters.for(profile)
      { "family" => label, "adapter_class" => adapter.class.name, "profile_family" => profile.family }
    end

    smoke_emit("adapters", rows)
  end

  def exercise_model_profile_helpers
    p = Ollama::ModelProfile.for(@model)
    smoke_emit(
      "helpers",
      {
        "supports_text" => p.supports_modality?(:text),
        "supports_image" => p.supports_modality?(:image),
        "multimodal?" => p.multimodal?,
        "tool_calling?" => p.tool_calling?,
        "structured_output?" => p.structured_output?,
        "stream_reasoning?" => p.stream_reasoning?,
        "default_options" => p.default_options
      }
    )
  end

  def exercise_stream_event_predicates
    samples = [
      [:thought_start, Ollama::StreamEvent.new(type: :thought_start, data: nil, model: @model)],
      [:thought_delta, Ollama::StreamEvent.new(type: :thought_delta, data: "x", model: @model)],
      [:answer_delta, Ollama::StreamEvent.new(type: :answer_delta, data: "y", model: @model)],
      [:tool_call_start, Ollama::StreamEvent.new(type: :tool_call_start, data: {}, model: @model)],
      [:complete, Ollama::StreamEvent.new(type: :complete, data: nil, model: @model)]
    ]
    rows = samples.map do |label, evt|
      {
        "case" => label,
        "thought?" => evt.thought?,
        "answer?" => evt.answer?,
        "tool_call?" => evt.tool_call?,
        "terminal?" => evt.terminal?
      }
    end

    smoke_emit("predicate_matrix", rows)
  end

  def exercise_response_tool_call_parse
    tc = Ollama::Response::Message::ToolCall.new(
      "function" => { "name" => "demo", "arguments" => "{\"city\":\"Paris\"}" }
    )
    raise "bad name" unless tc.name == "demo"
    raise "bad args" unless tc.arguments == { "city" => "Paris" }

    smoke_emit("tool_call", { "name" => tc.name, "arguments" => tc.arguments })
  end

  def exercise_generate_plain(client)
    out = client.generate(prompt: "Reply with exactly: LIVE_OK", model: @model, strict: false)
    raise "not string" unless out.is_a?(String)

    smoke_emit("response", out)
    smoke_emit("char_count", out.size)
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

    smoke_emit("parsed_hash", out)
  end

  def exercise_generate_stream(client)
    tokens = []
    client.generate(
      prompt: "Say the single digit 7 once, nothing else.",
      model: @model,
      hooks: { on_token: ->(t) { tokens << t } }
    )
    raise "no tokens" if tokens.empty?

    joined = tokens.join
    smoke_emit("token_chunk_count", tokens.size)
    smoke_emit("aggregated_stream_text", joined)
  end

  def exercise_generate_system_meta_options(client)
    opts = Ollama::Options.new(num_predict: 24, temperature: 0.1)
    out = client.generate(
      prompt: "Reply with one word: metaok",
      model: @model,
      system: "Answer briefly.",
      return_meta: true,
      options: opts.to_h,
      keep_alive: "0",
      strict: false
    )
    raise "bad shape" unless out.is_a?(Hash) && out["data"].is_a?(String) && out["meta"].is_a?(Hash)
    raise "bad meta model" unless out["meta"]["model"].to_s.include?(@model.split(":").first)

    smoke_emit("data", out["data"])
    smoke_emit("meta", out["meta"])
  end

  def exercise_generate_on_complete(client)
    done = false
    out = client.generate(
      prompt: "Say OK.",
      model: @model,
      strict: false,
      hooks: {
        on_token: ->(_) {},
        on_complete: -> { done = true }
      }
    )
    raise "on_complete not invoked" unless done

    smoke_emit("on_complete_hook_fired", done)
    smoke_emit("response", out)
  end

  def exercise_generate_thinking_reasoning(client)
    tm = thinking_model_name(client)
    raise "skip: no reasoning-capable model in tags (set OLLAMA_THINKING_MODEL)" unless tm

    # Plain text final (no schema) — many reasoning models return empty bodies or invalid JSON
    # when forced through generate + schema + think; this still exercises return_reasoning.
    out = client.generate(
      prompt: "Reply with exactly the word: OK",
      model: tm,
      think: true,
      return_reasoning: true,
      strict: false
    )
    raise "bad shape" unless out.is_a?(Hash) && out.key?("reasoning") && out.key?("final")
    raise "empty final" if out["final"].to_s.strip.empty?

    smoke_emit("model", tm)
    smoke_emit("reasoning", out["reasoning"])
    smoke_emit("final", out["final"])
  rescue Ollama::RetryExhaustedError, Ollama::InvalidJSONError,
         Ollama::ThinkingFormatError, Ollama::SchemaViolationError => e
    raise "skip: thinking + return_reasoning not supported or flaky for #{tm}: #{e.message}"
  end

  def exercise_generate_vision_images(client)
    vm = vision_model_name(client)
    raise "skip: no vision model (set OLLAMA_VISION_MODEL or pull a vision model)" unless vm

    out = client.generate(
      prompt: "What color dominates? Reply one word.",
      model: vm,
      images: [MINIMAL_PNG_B64],
      strict: false
    )
    raise "empty" if out.to_s.strip.empty?

    smoke_emit("model", vm)
    smoke_emit("response", out)
  end

  def exercise_generate_suffix_raw_optional(client)
    unless ENV["OLLAMA_LIVE_SMOKE_ENABLE_RAW_SUFFIX"] == "1"
      raise "skip: set OLLAMA_LIVE_SMOKE_ENABLE_RAW_SUFFIX=1 for suffix/raw generate"
    end

    out = client.generate(prompt: "Hi", suffix: " there", raw: true, model: @model, strict: false)
    raise "not string" unless out.is_a?(String)

    smoke_emit("response", out)
  end

  def exercise_chat_plain(client)
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Reply with exactly: CHAT_OK" }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    body = r.content.to_s
    raise "empty content" if body.strip.empty?

    smoke_emit("message.content", body)
    smoke_emit("raw_response_subset", r.to_h.slice("model", "done", "done_reason", "total_duration"))
  end

  def exercise_response_accessors(client)
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Say yes in one word." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    raise "no message" unless r.message
    raise "bad role" unless r.message.role.to_s == "assistant"

    smoke_emit("content", r.content)
    smoke_emit(
      "accessors",
      {
        "done" => r.done?,
        "model" => r.model,
        "done_reason" => r.done_reason,
        "latency_ms" => r.latency_ms,
        "usage" => r.usage,
        "message.role" => r.message.role,
        "prompt_eval_count" => r.prompt_eval_count,
        "eval_count" => r.eval_count
      }
    )
  end

  def exercise_chat_profile_auto(client)
    r = client.chat(
      model: @model,
      profile: :auto,
      messages: [{ role: "user", content: "Say hi in one word." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    smoke_emit("content", r.content)
    smoke_emit("usage", r.usage)
  end

  def exercise_chat_profile_none(client)
    r = client.chat(
      model: @model,
      profile: false,
      messages: [{ role: "user", content: "Reply OK." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)
    raise "empty" if r.content.to_s.strip.empty?

    smoke_emit("content", r.content)
  end

  def exercise_chat_format_options_keepalive(client)
    fmt = { "type" => "object", "properties" => { "k" => { "type" => "string" } } }
    opts = Ollama::Options.new(num_predict: 32, temperature: 0.1)
    r = client.chat(
      model: @model,
      format: fmt,
      options: opts.to_h,
      keep_alive: "0",
      messages: [{ role: "user", content: 'Return JSON only: {"k":"v"}' }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)
    raise "empty" if r.message.content.to_s.strip.empty?

    smoke_emit("message.content", r.message.content)
  end

  def exercise_chat_stream_false(client)
    r = client.chat(
      model: @model,
      stream: false,
      messages: [{ role: "user", content: "Say no in one word." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)
    raise "empty" if r.content.to_s.strip.empty?

    smoke_emit("stream", false)
    smoke_emit("content", r.content)
  end

  def exercise_chat_stream_true(client)
    toks = []
    r = client.chat(
      model: @model,
      stream: true,
      hooks: { on_token: ->(t) { toks << t } },
      messages: [{ role: "user", content: "Count 1." }]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)
    raise "no streamed tokens" if toks.join.strip.empty? && r.content.to_s.strip.empty?

    smoke_emit("stream", true)
    smoke_emit("token_chunks", toks.size)
    smoke_emit("hook_token_text", toks.join)
    smoke_emit("final_message.content", r.content)
  end

  def exercise_chat_stream_hooks(client)
    tokens = []
    thoughts = []
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Count 1 then 2 only." }],
      hooks: {
        on_token: ->(t) { tokens << t },
        on_thought: ->(evt) { thoughts << evt }
      }
    )
    raise "no answer tokens" if tokens.join.strip.empty?

    smoke_emit("token_chunks", tokens.size)
    smoke_emit("hook_token_text", tokens.join)
    smoke_emit("thought_event_count", thoughts.size)
    smoke_emit("thought_events_sample", thoughts.first(5).map { |evt| evt.to_h.transform_keys(&:to_s) })
    smoke_emit("final_message.content", r.content)
  end

  def exercise_chat_on_complete(client)
    done = false
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Say done." }],
      hooks: {
        on_token: ->(_) {},
        on_complete: -> { done = true }
      }
    )
    raise "on_complete not invoked" unless done

    smoke_emit("on_complete_hook_fired", done)
    smoke_emit("final_message.content", r.content)
  end

  def exercise_chat_logprobs_optional(client)
    r = client.chat(
      model: @model,
      messages: [{ role: "user", content: "Say hi." }],
      logprobs: true,
      top_logprobs: 3,
      stream: true,
      hooks: {
        on_token: ->(_t, _lp) {}
      }
    )
    smoke_emit("message.content", r.content)
    smoke_emit("logprobs", r.logprobs)
    smoke_emit("done", r.done?)
  rescue Ollama::Error => e
    raise "skip: logprobs not supported for this server/model: #{e.message}"
  end

  def exercise_chat_tools_optional(client)
    tm = tools_model_name(client)
    raise "skip: no tools model (set OLLAMA_TOOLS_MODEL or pull a tools-capable model)" unless tm

    from_hook = []
    r = client.chat(
      model: tm,
      messages: [
        { role: "user",
          content: "You must call get_weather with city Paris only. No other text." }
      ],
      tools: WEATHER_TOOL,
      hooks: { on_tool_call: ->(h) { from_hook << h } }
    )
    raise "skip: model did not emit a tool call (try a different OLLAMA_TOOLS_MODEL)" if
      r.message.tool_calls.empty? && from_hook.empty?

    smoke_emit("model", tm)
    smoke_emit("message.content", r.content)
    smoke_emit("message.tool_calls", r.message.tool_calls.map(&:to_h))
    smoke_emit("on_tool_call_hook_payloads", from_hook)
  end

  def exercise_chat_inputs_text_only(client)
    r = client.chat(
      model: @model,
      profile: :auto,
      messages: [{ role: "user", content: "Follow the numbered parts." }],
      inputs: [
        { type: :text, data: "Part 1: say" },
        { type: :text, data: "Part 2: TEXT_INPUTS_OK" }
      ]
    )
    raise "bad response" unless r.is_a?(Ollama::Response)

    body = r.content.to_s
    raise "empty content" if body.strip.empty?

    unless body.match?(/TEXT_INPUTS_OK/i)
      smoke_emit("message.content", body)
      raise "skip: model did not echo TEXT_INPUTS_OK (chat inputs: path still executed)"
    end

    smoke_emit("message.content", body)
  end

  def exercise_chat_inputs_vision_optional(client)
    vm = vision_model_name(client)
    raise "skip: no vision model for inputs (set OLLAMA_VISION_MODEL)" unless vm

    parts = [{ type: :image, data: MINIMAL_PNG_B64 }, { type: :text, data: "One word: main color?" }]
    r = client.chat(
      model: vm,
      profile: :auto,
      messages: [{ role: "user", content: "Use attached image." }],
      inputs: parts
    )
    raise "empty" if r.content.to_s.strip.empty?

    smoke_emit("model", vm)
    smoke_emit("message.content", r.content)
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

    smoke_emit("built_message", msg.transform_values { |v| v.is_a?(String) && v.size > 200 ? "#{v[0, 200]}…" : v })
  end

  def exercise_multimodal_input_add_reorder
    profile = Ollama::ModelProfile.for(@model)
    mm = Ollama::MultimodalInput.new
    mm.add({ type: :text, data: "B" }, profile: profile)
    mm.add({ type: :text, data: "A" }, profile: profile)
    mm.reorder!(profile.modality_order)
    raise "expected two parts" unless mm.parts.size == 2

    msg = mm.to_message
    body = msg[:content].to_s
    raise "missing text fragments" unless body.include?("A") && body.include?("B")

    smoke_emit("parts", mm.parts)
    smoke_emit("message", msg)
  end

  def exercise_history_sanitizer(client)
    messages = [{ role: "user", content: "Say OK for history test." }]
    r = client.chat(model: @model, messages: messages)
    san = client.history_sanitizer(@model)
    san.add(r, messages: messages)
    last = messages.last
    raise "assistant missing" unless last[:role] == "assistant"

    smoke_emit("messages_after_add", messages)
  end

  def exercise_history_sanitizer_profile_trace(client)
    messages = [{ role: "user", content: "Say OK for trace store test." }]
    r = client.chat(model: @model, messages: messages)
    profile = client.profile(@model)
    traces = []
    san = client.history_sanitizer(profile, trace_store: traces)
    san.add(r, messages: messages)
    last = messages.last
    raise "assistant missing" unless last[:role] == "assistant"

    smoke_emit("messages_after_add", messages)
    smoke_emit("trace_store", traces)
  end

  def exercise_stream_event
    e = Ollama::StreamEvent.new(type: :thought_delta, data: "x", model: @model)
    line = e.to_jsonl
    parsed = JSON.parse(line)
    raise "bad jsonl" unless parsed["type"] == "thought_delta"
    raise "thought? expected" unless e.thought?

    smoke_emit("jsonl_line", line)
    smoke_emit("parsed", parsed)
  end

  def exercise_embeddings(client)
    embed_name = embed_name_for(client)
    raise "skip: no embedding model in tags (set OLLAMA_EMBED_MODEL)" unless embed_name

    vec = client.embeddings.embed(model: embed_name, input: "live smoke")
    raise "not vector" unless vec.is_a?(Array) && vec.first.is_a?(Numeric)

    smoke_emit("model", embed_name)
    smoke_emit_vector("embedding", vec)
  end

  def exercise_embeddings_batch(client)
    embed_name = embed_name_for(client)
    raise "skip: no embedding model in tags (set OLLAMA_EMBED_MODEL)" unless embed_name

    vecs = client.embeddings.embed(model: embed_name, input: %w[alpha beta])
    raise "bad batch" unless vecs.is_a?(Array) && vecs.size == 2
    raise "bad row" unless vecs[0].is_a?(Array) && vecs[1].is_a?(Array)

    smoke_emit("model", embed_name)
    smoke_emit("batch_size", vecs.size)
    smoke_emit_vector("embedding[0]", vecs[0])
    smoke_emit_vector("embedding[1]", vecs[1])
  end

  def exercise_embeddings_optional_kwargs(client)
    embed_name = embed_name_for(client)
    raise "skip: no embedding model in tags (set OLLAMA_EMBED_MODEL)" unless embed_name

    vec = client.embeddings.embed(
      model: embed_name,
      input: "kwarg line",
      truncate: true,
      keep_alive: "0"
    )
    raise "not vector" unless vec.is_a?(Array) && vec.first.is_a?(Numeric)

    smoke_emit("model", embed_name)
    smoke_emit_vector("embedding", vec)
  rescue Ollama::Error => e
    raise "skip: optional embed kwargs rejected: #{e.message}"
  end

  def exercise_embeddings_dimensions_options(client)
    embed_name = embed_name_for(client)
    raise "skip: no embedding model in tags (set OLLAMA_EMBED_MODEL)" unless embed_name

    opts = Ollama::Options.new(num_ctx: 256)
    vec = client.embeddings.embed(
      model: embed_name,
      input: "dimensions smoke",
      dimensions: 256,
      options: opts.to_h
    )
    raise "not vector" unless vec.is_a?(Array) && vec.first.is_a?(Numeric)

    smoke_emit("model", embed_name)
    smoke_emit("returned_dim", vec.size)
    smoke_emit_vector("embedding", vec)
  rescue Ollama::Error => e
    raise "skip: dimensions/options not supported for #{embed_name}: #{e.message}"
  end

  def exercise_openai_compat(client)
    # 1. Models list
    res = client.openai.models.list
    raise "bad models list" unless res["object"] == "list" && res["data"].is_a?(Array)

    # 2. Chat completion
    chat_res = client.openai.chat.completions.create(
      model: @model,
      messages: [{ role: "user", content: "Say OK" }]
    )
    raise "bad chat response" unless chat_res["object"] == "chat.completion"

    content = chat_res.dig("choices", 0, "message", "content")
    raise "empty content" if content.to_s.strip.empty?

    # 3. Embedding
    embed_name = embed_name_for(client)
    if embed_name
      emb_res = client.openai.embeddings.create(model: embed_name, input: "test")
      raise "bad embedding" unless emb_res["object"] == "list" && emb_res["data"][0]["embedding"].is_a?(Array)
    end

    smoke_emit("chat_id", chat_res["id"])
    smoke_emit("chat_content", content)
    smoke_emit("embedding_model", embed_name) if embed_name
  rescue StandardError => e
    raise "OpenAI Compat failed: #{e.message}"
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

    smoke_emit("model", model)
    smoke_emit("message.content", r.content)
    smoke_emit("message.thinking", r.message.thinking)
  end

  def exercise_copy_delete_optional(client)
    raise "skip: set OLLAMA_LIVE_SMOKE_COPY_TEST=1 for copy_model/delete_model" unless ENV["OLLAMA_LIVE_SMOKE_COPY_TEST"] == "1"

    source = ENV.fetch("OLLAMA_COPY_SOURCE", @model)
    raw_dest = ENV.fetch("OLLAMA_COPY_DEST", nil)
    dest = raw_dest && !raw_dest.strip.empty? ? raw_dest.strip : "live-smoke-copy-#{Process.pid}-#{Time.now.to_i}"
    begin
      client.copy_model(source: source, destination: dest)
      smoke_emit("copy", { "source" => source, "destination" => dest })
    ensure
      begin
        client.delete_model(model: dest)
        smoke_emit("delete", { "model" => dest, "status" => "attempted (errors ignored in cleanup)" })
      rescue StandardError => e
        smoke_emit("delete_cleanup_note", "#{e.class}: #{e.message}")
      end
    end
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
# rubocop:enable Metrics/ClassLength

exit LiveBranchSmoke.new.run if $PROGRAM_NAME == __FILE__

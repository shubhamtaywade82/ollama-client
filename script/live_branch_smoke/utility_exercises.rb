# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module LiveBranchSmokeUtilityExercises
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
end
# rubocop:enable Metrics/ModuleLength

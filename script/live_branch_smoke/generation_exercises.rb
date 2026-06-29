# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module LiveBranchSmokeGenerationExercises
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
end
# rubocop:enable Metrics/ModuleLength

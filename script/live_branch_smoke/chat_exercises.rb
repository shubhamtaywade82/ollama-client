# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module LiveBranchSmokeChatExercises
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
      tools: LiveBranchSmoke::WEATHER_TOOL,
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

    parts = [{ type: :image, data: LiveBranchSmoke::MINIMAL_PNG_B64 }, { type: :text, data: "One word: main color?" }]
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
end
# rubocop:enable Metrics/ModuleLength

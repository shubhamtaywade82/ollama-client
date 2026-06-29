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
#   OLLAMA_MODEL        — primary text model (default: qwen3.5:4b)
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

require_relative "live_branch_smoke/model_exercises"
require_relative "live_branch_smoke/generation_exercises"
require_relative "live_branch_smoke/chat_exercises"
require_relative "live_branch_smoke/utility_exercises"

# Live HTTP checks for models, chat, generate, embeddings, and public helpers.
class LiveBranchSmoke
  include LiveBranchSmokeModelExercises
  include LiveBranchSmokeGenerationExercises
  include LiveBranchSmokeChatExercises
  include LiveBranchSmokeUtilityExercises

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
    @model = ENV.fetch("OLLAMA_MODEL", "qwen3.5:4b")
    @gemma_model = ENV.fetch("OLLAMA_GEMMA_MODEL", nil)
    @embed_model = ENV.fetch("OLLAMA_EMBED_MODEL", nil)
    @passed = 0
    @skipped = 0
    @failed = 0
    pv = ENV.fetch("OLLAMA_SMOKE_PREVIEW_CHARS", "1200").to_i
    @preview_limit = pv.clamp(200, 32_768)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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

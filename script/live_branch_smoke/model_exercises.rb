# frozen_string_literal: true

module LiveBranchSmokeModelExercises
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
end

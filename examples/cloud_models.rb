# frozen_string_literal: true

require_relative "../lib/ollama_client"
require "json"

begin
  require "concurrent"
rescue LoadError
  warn "Error: concurrent-ruby is required. Add it to your Gemfile."
  exit 1
end

# ---------------------------------------------------------------------------
# Cloud Model Accessibility Probe
#
# Lists all models available on Ollama Cloud and probes each one to determine
# whether the current authenticated account can run inference against it.
# Results are printed as JSON to stdout and saved to examples/free_catalog.json.
# ---------------------------------------------------------------------------

OUTPUT_FILE = File.join(__dir__, "free_catalog.json").freeze
ONLY_ACCESSIBLE = ARGV.include?("--accessible")
NAMES_ONLY = ARGV.include?("--names-only")

api_key = ENV.fetch("OLLAMA_API_KEY", nil)
if api_key.nil? || api_key.empty?
  warn <<~USAGE
    Usage: OLLAMA_API_KEY=<your-key> bundle exec ruby examples/cloud_models.rb

    Please set the OLLAMA_API_KEY environment variable to your Ollama Cloud API key.
  USAGE
  exit 1
end

config = Ollama::Config.new
config.base_url = "https://ollama.com"
config.api_key  = api_key
config.timeout  = 30
config.retries  = 0

client = Ollama::Client.new(config: config)

# Fetch the public model catalog from Ollama Cloud.
begin
  catalog = client.raw.get("/api/tags")
rescue Ollama::Error => e
  warn "Failed to fetch model catalog: #{e.message}"
  exit 1
end

models = catalog["models"] || []
names  = models.map { |m| m["name"] }.compact.sort

catalog_capabilities = {}
models.each do |m|
  name = m["name"]
  next unless name

  catalog_capabilities[name] = Ollama::Capabilities.for(m)
end

# Also try the OpenAI-compatible endpoint for a broader model list.
begin
  openai_models = client.raw.get("/v1/models")
  openai_names  = (openai_models["data"] || []).map { |m| m["id"] }.compact
  added = openai_names - names
  names = (names + openai_names).uniq.sort
  warn "/v1/models returned #{openai_names.length} model(s), #{added.length} new"
rescue Ollama::Error => e
  warn "Warning: could not fetch /v1/models (#{e.message}), using /api/tags only"
end

# Known Ollama Cloud models not always surfaced by /api/tags.
EXTRA_MODELS = %w[
  gemma4:12b
  gemma4:26b
  gemma4:31b
  qwen3.5:0.8b
  qwen3.5:2b
  qwen3.5:4b
  qwen3.5:9b
  qwen3.5:27b
  qwen3.5:35b
  qwen3.5:122b
  mistral-large-3:123b
  mistral-large-3:400b
  nemotron-3-nano:4b
  gemini-3-flash-preview
  glm-5
  kimi-k2.5
].freeze

extra = EXTRA_MODELS - names
names = (names + extra).uniq.sort
warn "Added #{extra.length} extra known cloud model(s) to probe"

if names.empty?
  puts "[]"
  exit 0
end

warn "Probing #{names.length} cloud model(s) with 10 concurrent threads..."

results = Concurrent::Array.new
pool    = Concurrent::FixedThreadPool.new(10)

names.each do |name|
  pool.post do
    sleep(rand * 0.2)

    result = { name: name, accessible: false, reason: nil, capabilities: catalog_capabilities[name] || {} }

    begin
      client.chat(
        model: name,
        messages: [{ role: "user", content: "ping" }],
        options: { num_predict: 1 }
      )

      result[:accessible] = true
    rescue Ollama::UnauthorizedError
      result[:reason] = "unauthorized"
    rescue Ollama::ModelUnavailableError
      result[:reason] = "unavailable"
    rescue Ollama::NotFoundError
      result[:reason] = "not_found"
    rescue Ollama::HTTPError => e
      reason = case e.status_code
               when 402 then "usage_limit"
               when 403 then "plan_restricted"
               when 429 then "rate_limited"
               else "http_error"
               end
      result[:reason] = reason
    rescue Ollama::TimeoutError
      result[:reason] = "timeout"
    rescue StandardError => e
      result[:reason] = "error: #{e.class}: #{e.message}"
    end

    results << result
  end
end

pool.shutdown
pool.wait_for_termination

sorted = results.sort_by { |r| r[:name] }

if ONLY_ACCESSIBLE
  sorted = sorted.select { |r| r[:accessible] }
  warn "Filtering to #{sorted.length} accessible model(s) (--accessible)"
end

if NAMES_ONLY
  sorted.each { |r| puts r[:name] }
else
  json = JSON.pretty_generate(sorted)
  puts json
  File.write(OUTPUT_FILE, json + "\n")
  warn "Saved free catalog to #{OUTPUT_FILE}"
end

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
# ---------------------------------------------------------------------------

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

if names.empty?
  puts "[]"
  exit 0
end

warn "Probing #{names.length} cloud model(s) with 10 concurrent threads..."

results = Concurrent::Array.new
pool    = Concurrent::FixedThreadPool.new(10)

names.each do |name|
  pool.post do
    # Jitter to avoid thundering-herd against the API.
    sleep(rand * 0.2)

    begin
      client.chat(
        model: name,
        messages: [{ role: "user", content: "ping" }],
        options: { num_predict: 1 }
      )

      results << { name: name, accessible: true, reason: nil }
    rescue Ollama::UnauthorizedError
      results << { name: name, accessible: false, reason: "unauthorized" }
    rescue Ollama::ModelUnavailableError
      results << { name: name, accessible: false, reason: "unavailable" }
    rescue Ollama::NotFoundError
      results << { name: name, accessible: false, reason: "not_found" }
    rescue Ollama::HTTPError => e
      reason = case e.status_code
               when 402 then "usage_limit"
               when 403 then "plan_restricted"
               when 429 then "rate_limited"
               else "http_error"
               end
      results << { name: name, accessible: false, reason: reason }
    rescue Ollama::TimeoutError
      results << { name: name, accessible: false, reason: "timeout" }
    rescue StandardError => e
      results << { name: name, accessible: false, reason: "error: #{e.class}: #{e.message}" }
    end
  end
end

pool.shutdown
pool.wait_for_termination

sorted = results.sort_by { |r| r[:name] }
puts JSON.pretty_generate(sorted)

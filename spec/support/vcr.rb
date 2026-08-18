# frozen_string_literal: true

require "vcr"

# Cassettes hold real Ollama Cloud responses, recorded once against a live
# server and replayed from then on. Day-to-day `bundle exec rspec` never
# touches the network — this satisfies the project's "no live Ollama in
# tests" rule (CLAUDE.md) exactly the way stub_request did, just with
# real response bodies instead of hand-written ones.
#
# Recording / re-recording:
#   OLLAMA_API_KEY=... VCR_RECORD=1 bundle exec rspec spec/ollama/client_vcr_spec.rb
#
# VCR_RECORD=1 switches the record mode to :once (record if the cassette
# file doesn't exist yet, otherwise replay — never re-records an existing
# cassette). Delete a cassette file first to force a fresh recording.
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  config.default_cassette_options = {
    record: ENV["VCR_RECORD"] ? :once : :none,
    match_requests_on: %i[method uri body],
    allow_playback_repeats: false
  }

  # Never let a real API key reach a committed cassette file.
  config.filter_sensitive_data("<OLLAMA_API_KEY>") { ENV.fetch("OLLAMA_API_KEY", nil) }
  config.filter_sensitive_data("<OLLAMA_API_KEY>") do |interaction|
    auth = interaction.request.headers["Authorization"]&.first
    auth&.sub(/\ABearer\s+/, "")
  end
end

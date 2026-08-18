# frozen_string_literal: true

# Builds a client configured against Ollama Cloud for :vcr-tagged specs.
#
# During replay (the normal case — no OLLAMA_API_KEY set), the placeholder
# key is fine: VCR's default match_requests_on is [:method, :uri, :body],
# which never inspects headers, so the Authorization value has no bearing
# on cassette matching.
module VCRClientHelper
  CLOUD_MODEL = "gpt-oss:20b"

  def vcr_client(model: CLOUD_MODEL, timeout: 60)
    Ollama::Client.new(config: Ollama::Config.new.tap do |c|
      c.base_url = "https://ollama.com"
      c.api_key = ENV.fetch("OLLAMA_API_KEY", "placeholder-vcr-key")
      c.model = model
      c.timeout = timeout
      c.retries = 0
    end)
  end
end

RSpec.configure do |config|
  config.include VCRClientHelper, :vcr
end

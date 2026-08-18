# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client do
  let(:config) do
    Ollama::Config.new.tap do |c|
      c.base_url = "https://ollama.com"
      c.api_key = "test-api-key"
      c.retries = 0
    end
  end
  let(:client) { described_class.new(config: config) }

  describe "#web_search" do
    it "sends the query and returns the results array" do
      stub_request(:post, "https://ollama.com/api/web_search")
        .with(
          body: { query: "what is ollama?" }.to_json,
          headers: { "Authorization" => "Bearer test-api-key" }
        )
        .to_return(
          status: 200,
          body: { results: [{ title: "Ollama", url: "https://ollama.com", content: "..." }] }.to_json
        )

      results = client.web_search(query: "what is ollama?")

      expect(results).to eq([{ "title" => "Ollama", "url" => "https://ollama.com", "content" => "..." }])
    end

    it "includes max_results when given" do
      stub_request(:post, "https://ollama.com/api/web_search")
        .with(body: { query: "ruby", max_results: 3 }.to_json)
        .to_return(status: 200, body: { results: [] }.to_json)

      client.web_search(query: "ruby", max_results: 3)

      expect(WebMock).to have_requested(:post, "https://ollama.com/api/web_search")
        .with(body: { query: "ruby", max_results: 3 }.to_json)
    end

    it "raises UnauthorizedError on 401" do
      stub_request(:post, "https://ollama.com/api/web_search")
        .to_return(status: 401, body: { error: "invalid api key" }.to_json)

      expect { client.web_search(query: "x") }.to raise_error(Ollama::UnauthorizedError)
    end
  end

  describe "#web_fetch" do
    it "sends the url and returns title/content/links" do
      stub_request(:post, "https://ollama.com/api/web_fetch")
        .with(body: { url: "https://ollama.com" }.to_json)
        .to_return(
          status: 200,
          body: { title: "Ollama", content: "...", links: ["https://ollama.com/download"] }.to_json
        )

      result = client.web_fetch(url: "https://ollama.com")

      expect(result).to eq(
        "title" => "Ollama",
        "content" => "...",
        "links" => ["https://ollama.com/download"]
      )
    end
  end
end

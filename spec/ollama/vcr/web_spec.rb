# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Client, "web endpoints (VCR)", :vcr do
  let(:client) { vcr_client }

  describe "#web_search" do
    it "returns results for a query", vcr: { cassette_name: "web/web_search_returns_results" } do
      results = client.web_search(query: "ollama ruby client gem")

      expect(results).to be_an(Array)
      expect(results).not_to be_empty
      expect(results.first).to include("title", "url", "content")
    end
  end

  describe "#web_fetch" do
    it "returns page content for a url", vcr: { cassette_name: "web/web_fetch_returns_content" } do
      result = client.web_fetch(url: "https://ollama.com")

      expect(result).to include("title", "content")
    end
  end
end

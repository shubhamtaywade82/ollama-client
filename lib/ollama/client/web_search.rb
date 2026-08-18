# frozen_string_literal: true

module Ollama
  class Client
    # Ollama Cloud web search & fetch endpoints.
    #
    # Both require an Ollama Cloud API key (config.api_key / OLLAMA_API_KEY)
    # and a client configured against the cloud host, e.g.:
    #   config.base_url = "https://ollama.com"
    #
    # @see https://docs.ollama.com/capabilities/web-search
    module WebSearch
      # Search the web via Ollama Cloud.
      #
      # @param query [String] Search query (required)
      # @param max_results [Integer, nil] Max results to return (server default 5, max 10)
      # @return [Array<Hash>] Results, each with "title", "url", "content"
      def web_search(query:, max_results: nil)
        body = { query: query }
        body[:max_results] = max_results if max_results
        res = execute_management_request("/api/web_search", body: body)
        JSON.parse(res.body)["results"] || []
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse web_search response: #{e.message}"
      end

      # Fetch and extract content from a URL via Ollama Cloud.
      #
      # @param url [String] URL to fetch (required)
      # @return [Hash] "title", "content", "links"
      def web_fetch(url:)
        res = execute_management_request("/api/web_fetch", body: { url: url })
        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse web_fetch response: #{e.message}"
      end
    end
  end
end

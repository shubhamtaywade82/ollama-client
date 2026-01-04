# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"

module Ollama
  # Main client class for interacting with Ollama API
  class Client
    def initialize(config: OllamaClient.config)
      @config = config
      @uri = URI("#{@config.base_url}/api/generate")
    end

    def generate(prompt:, schema:)
      attempts = 0

      begin
        attempts += 1
        raw = call_api(prompt)
        parsed = JSON.parse(raw)
        SchemaValidator.validate!(parsed, schema)
        parsed
      rescue TimeoutError, InvalidJSONError, SchemaViolationError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end

    private

    def call_api(prompt)
      req = Net::HTTP::Post.new(@uri)
      req["Content-Type"] = "application/json"

      req.body = {
        model: @config.model,
        prompt: prompt,
        stream: false,
        temperature: @config.temperature,
        top_p: @config.top_p,
        num_ctx: @config.num_ctx
      }.to_json

      res = Net::HTTP.start(
        @uri.hostname,
        @uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      raise Error, "HTTP #{res.code}: #{res.message}" unless res.is_a?(Net::HTTPSuccess)

      body = JSON.parse(res.body)
      body["response"]
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse API response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
  end
end

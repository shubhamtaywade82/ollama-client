# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"
require_relative "embeddings"
require_relative "response"
require_relative "client/chat"
require_relative "client/generate"
require_relative "client/model_management"

module Ollama
  # Main client class for interacting with the Ollama API.
  #
  # Provides methods for all 12 Ollama API endpoints, organized into modules:
  # - Chat: multi-turn conversations with tool support
  # - Generate: prompt-to-completion with structured output
  # - ModelManagement: CRUD, pull/push, list, show, version
  class Client
    include Chat
    include Generate
    include ModelManagement

    attr_reader :embeddings

    def initialize(config: nil)
      @config = config || default_config
      @base_uri = URI(@config.base_url)
      @embeddings = Embeddings.new(@config)
    end

    private

    # Build options hash from user-provided options merged with config defaults
    def build_options(user_options = nil)
      opts = {
        temperature: @config.temperature,
        top_p: @config.top_p,
        num_ctx: @config.num_ctx
      }

      if user_options.is_a?(Hash)
        opts.merge!(user_options.transform_keys(&:to_sym))
      elsif user_options.respond_to?(:to_h)
        opts.merge!(user_options.to_h.transform_keys(&:to_sym))
      end

      opts.compact
    end

    def default_config
      if defined?(OllamaClient)
        OllamaClient.config.dup
      else
        Config.new
      end
    end

    # Shared HTTP request helper for simple (non-streaming) requests
    def http_request(uri, req, read_timeout: @config.timeout)
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        read_timeout: read_timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    def handle_http_error(res, requested_model: nil)
      status_code = res.code.to_i
      requested_model ||= @config.model

      error_message = extract_error_message(res) || res.message

      raise NotFoundError.new(error_message, requested_model: requested_model) if status_code == 404

      raise HTTPError.new("HTTP #{res.code}: #{error_message}", status_code)
    end

    # Parse error message from JSON response body (Ollama returns {"error": "..."})
    def extract_error_message(res)
      body = res.body
      return nil if body.nil? || body.empty?

      parsed = JSON.parse(body)
      parsed["error"] if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end

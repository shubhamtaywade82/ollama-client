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
require_relative "capabilities"
require_relative "model_profile"
require_relative "stream_event"
require_relative "prompt_adapters"
require_relative "multimodal_input"
require_relative "history_sanitizer"

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

    # Return the capability profile for a model name.
    # Profiles drive prompt adaptation, streaming event routing, and defaults.
    #
    # @param model_name [String]
    # @return [Ollama::ModelProfile]
    def profile(model_name)
      ModelProfile.for(model_name)
    end

    # Build a history sanitizer appropriate for a model profile.
    # Convenience method for multi-turn agent loops.
    #
    # @param model_name_or_profile [String, ModelProfile]
    # @param trace_store [Array, nil]
    # @return [Ollama::HistorySanitizer]
    def history_sanitizer(model_name_or_profile, trace_store: nil)
      p = model_name_or_profile.is_a?(ModelProfile) ? model_name_or_profile : profile(model_name_or_profile)
      HistorySanitizer.for(p, trace_store: trace_store)
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

    # Like build_options but applies model-family defaults first so that
    # profile-recommended settings (e.g. Gemma 4 temperature=1.0) take
    # precedence over client config defaults, while explicit user options
    # always win.
    def build_options_with_profile(user_options, active_profile)
      opts = {
        temperature: @config.temperature,
        top_p: @config.top_p,
        num_ctx: @config.num_ctx
      }

      opts.merge!(active_profile.default_options) if active_profile

      if user_options.is_a?(Hash)
        opts.merge!(user_options.transform_keys(&:to_sym))
      elsif user_options.respond_to?(:to_h)
        opts.merge!(user_options.to_h.transform_keys(&:to_sym))
      end

      opts.compact
    end

    # Resolve a profile value into a ModelProfile instance.
    # :auto (default) → detect from model name string.
    def resolve_profile(model_name, profile_arg)
      return nil if profile_arg == false || profile_arg == :none
      return profile_arg if profile_arg.is_a?(ModelProfile)

      ModelProfile.for(model_name.to_s)
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
      @config.apply_auth_to(req)
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        **@config.http_connection_options(uri, read_timeout: read_timeout)
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

    def emit_response_hook(raw, meta)
      hook = @config.on_response
      return unless hook.respond_to?(:call)

      hook.call(raw, meta)
    rescue StandardError
      nil
    end

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

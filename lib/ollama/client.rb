# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"
require_relative "rate_limit_handler"
require_relative "transport"
require_relative "providers"
require_relative "embeddings"
require_relative "response"
require_relative "params"
require_relative "http_error_handler"
require_relative "pipeline"
require_relative "events"
require_relative "plugins"
require_relative "client/chat"
require_relative "client/generate"
require_relative "client/model_management"
require_relative "client/web_search"
require_relative "client/raw"
require_relative "client/openai_compat"
require_relative "client/tool_intent"
require_relative "capabilities"
require_relative "model_profile"
require_relative "stream_event"
require_relative "prompt_adapters"
require_relative "multimodal_input"
require_relative "history_sanitizer"
require_relative "tool_intent"
require_relative "chat_response"
require_relative "attachment"
require_relative "messages"
require_relative "prompt"
require_relative "tool_dsl"
require_relative "schema_dsl"

module Ollama
  # Main client class for interacting with the Ollama API.
  #
  # Provides methods for all Ollama API endpoints, organized into modules:
  # - Chat: multi-turn conversations with tool support
  # - Generate: prompt-to-completion with structured output
  # - ModelManagement: CRUD, pull/push, list, show, version
  # - WebSearch: Ollama Cloud web_search / web_fetch endpoints
  class Client
    include Chat
    include Generate
    include ModelManagement
    include WebSearch
    include ToolIntent
    include Raw
    include OpenAICompat
    include RateLimitHandler
    include HttpErrorHandler

    attr_reader :embeddings, :provider, :config, :pipeline, :events

    def initialize(config: nil)
      @config = config || default_config
      @base_uri = URI(@config.base_url)
      @transport = Transport.build(@config)
      @provider = Providers.build(@config, @transport)
      # Initialize pipeline with default middleware
      @events = Events.new
      @pipeline = Pipeline.new(@transport, events: @events)
      @embeddings = Embeddings.new(@config, transport: @transport, pipeline: @pipeline)

      # Apply global plugins
      Ollama.apply_plugins(self)
    end

    # Add middleware to the pipeline
    # @param middleware [Class, Ollama::Middleware] Middleware class or instance
    # @param options [Hash] Options to pass to middleware constructor
    # @return [Ollama::Client] self
    def use(middleware, **options)
      @pipeline = @pipeline.use(middleware, **options)
      @embeddings.pipeline = @pipeline if @embeddings.respond_to?(:pipeline=)
      self
    end

    # Subscribe to pipeline events
    # @param event [Symbol] Event name (:before_request, :after_request, :request_error, etc.)
    # @param block [Proc] Callback to execute when event is published
    # @return [Proc] The subscribed block
    def on(event, &block)
      @events.subscribe(event, &block)
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

    # Execute a request through the pipeline
    # @param request [Ollama::Request] The request to execute
    # @return [Ollama::Transport::Response] The transport response
    def execute(request)
      @pipeline.call(request)
    end

    # Execute a streaming request through the pipeline
    # @param request [Ollama::Request] The request to execute
    # @yield [chunk] Yields each chunk of the streaming response
    # @return [Ollama::Transport::Response] The final transport response
    def execute_stream(request, &block)
      @pipeline.stream(request, &block)
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
      return nil if [false, :none].include?(profile_arg)
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

    def emit_response_hook(raw, meta)
      hook = @config.on_response
      return unless hook.respond_to?(:call)

      hook.call(raw, meta)
    rescue StandardError
      nil
    end

    # Shared HTTP request helper for simple (non-streaming) requests
    # Used by modules that haven't been migrated to the pipeline yet
    def http_request(uri, req, read_timeout: @config.timeout)
      with_rate_limit_key_rotation do |api_key|
        @config.apply_auth_to(req, api_key: api_key)
        res = @transport.request(uri: uri, request: req, read_timeout: read_timeout)
        raise Errors.from_response(res) if res.code.to_i == 429

        res
      end
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
  end
end

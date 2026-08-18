# frozen_string_literal: true

require_relative "base"

module Ollama
  module Policies
    # CapabilityValidation policy - validates model capabilities before request
    class CapabilityValidation < Base
      attr_reader :enabled, :cache, :hooks

      # @param enabled [Boolean] Whether capability validation is enabled (default: true)
      # @param cache [Object] Cache store for model profiles (must respond to read/write)
      # @param cache_ttl [Integer] Cache TTL in seconds (default: 3600)
      # @param hooks [Hash] Optional hooks: :capability_missing, :model_unknown
      def initialize(enabled: true, cache: nil, cache_ttl: 3600, hooks: {})
        super()
        @enabled = enabled
        @cache = cache
        @cache_ttl = cache_ttl
        @hooks = hooks
      end

      def call(request, env = {})
        return @app.call(request, env) unless @enabled

        # Skip if no model or endpoint doesn't require capabilities
        return @app.call(request, env) unless validate_capabilities?(request)

        model = request.model
        return @app.call(request, env) unless model

        # Get model profile (with caching)
        profile = get_model_profile(model)

        # Check capabilities
        missing = check_capabilities(request, profile)
        return @app.call(request, env) if missing.empty?

        @hooks[:capability_missing]&.call(missing, model, env)

        raise UnsupportedCapabilityError,
              "Model '#{model}' does not support: #{missing.join(", ")}"
      end

      def stream(request, env = {}, &block)
        call(request, env) { |req, env| @app.stream(req, env, &block) }
      end

      private

      def validate_capabilities?(request)
        # Only validate for endpoints that may require specific capabilities
        %i[chat generate embeddings].include?(request.endpoint)
      end

      def get_model_profile(model)
        cache_key = "model_profile:#{model}"

        if @cache && (cached = @cache.read(cache_key))
          return cached
        end

        # Get profile from capabilities module
        require_relative "../../capabilities"
        profile = Ollama::Capabilities.for(model)

        @cache&.write(cache_key, profile, expires_in: @cache_ttl)

        profile
      end

      def check_capabilities(request, profile)
        missing = []

        # Check thinking capability
        missing << "thinking" if request.raw_options&.dig(:think) && !profile["thinking"]

        # Check vision capability
        missing << "vision" if request.raw_options&.dig(:images) && !profile["vision"]

        # Check tools capability
        missing << "tools" if request.raw_options&.dig(:tools) && !profile["tools"]

        # Check structured output capability
        missing << "structured_output" if request.raw_options&.dig(:format) && !profile["structured_output"]

        # Check embeddings capability
        missing << "embeddings" if request.endpoint == :embeddings && !profile["embeddings"]

        missing
      end
    end
  end
end

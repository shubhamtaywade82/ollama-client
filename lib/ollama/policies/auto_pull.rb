# frozen_string_literal: true

require_relative "base"

module Ollama
  module Policies
    # AutoPull policy - automatically pulls missing models on 404
    class AutoPull < Base
      attr_reader :enabled, :allowed_patterns, :hooks

      # @param enabled [Boolean] Whether auto-pull is enabled (default: true)
      # @param allowed_patterns [Array<String>] Glob patterns for models allowed to be auto-pulled (default: ["*"])
      # @param hooks [Hash] Optional hooks: :before_pull, :after_pull
      def initialize(enabled: true, allowed_patterns: ["*"], hooks: {})
        super()
        @enabled = enabled
        @allowed_patterns = Array(allowed_patterns)
        @hooks = hooks
      end

      def call(request, env = {})
        return @app.call(request, env) unless @enabled && pullable?(request)

        attempt = 0
        max_attempts = 1

        loop do
          attempt += 1
          env[:auto_pull_attempt] = attempt

          begin
            response = @app.call(request, env)
            return response
          rescue NotFoundError => e
            raise unless pullable?(request) && attempt <= max_attempts

            model = extract_model(request, e)
            raise unless model

            # Check if model is allowed
            raise unless allowed?(model)

            @hooks[:before_pull]&.call(model, env)

            pull_model(model, env)

            @hooks[:after_pull]&.call(model, env)
          end
        end
      end

      def stream(request, env = {}, &block)
        @app.stream(request, env, &block)
      end

      private

      def pullable?(request)
        return false unless request.respond_to?(:model)
        return false if request.model.nil? || request.model.empty?

        # Only for endpoints that use models
        %i[chat generate embeddings show_model create_model pull push].include?(request.endpoint)
      end

      def extract_model(request, error)
        return request.model if request.respond_to?(:model) && request.model

        # Try to extract from error
        return unless error.respond_to?(:requested_model)

        error.requested_model
      end

      def allowed?(model)
        @allowed_patterns.any? { |pattern| File.fnmatch?(pattern, model) }
      end

      def pull_model(model, env)
        # Pull model using the client's pull method
        # This bypasses the policy pipeline to avoid recursion
        client = env[:client]
        return unless client.respond_to?(:pull)

        client.pull(model, stream: false)
      end
    end
  end
end

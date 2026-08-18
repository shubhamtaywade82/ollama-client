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

      MAX_RETRY_ATTEMPTS = 1
      PULLABLE_ENDPOINTS = %i[chat generate embeddings show_model create_model].freeze

      def around(request, env, &block)
        return block.call(request, env) unless @enabled && pullable?(request)

        attempt = 0

        loop do
          attempt += 1
          env[:auto_pull_attempt] = attempt

          begin
            return block.call(request, env)
          rescue NotFoundError
            raise unless attempt <= MAX_RETRY_ATTEMPTS

            model = request_model(request)
            raise unless model && allowed?(model)

            @hooks[:before_pull]&.call(model, env)

            pull_model(model, env)

            @hooks[:after_pull]&.call(model, env)
          end
        end
      end

      private

      def pullable?(request)
        PULLABLE_ENDPOINTS.include?(endpoint(request))
      end

      def allowed?(model)
        @allowed_patterns.any? { |pattern| File.fnmatch?(pattern, model) }
      end

      def pull_model(model, env)
        # Pull model using a client outside the policy chain to avoid recursion.
        client = env[:client] || Ollama.client
        return unless client.respond_to?(:pull)

        client.pull(model, stream: false)
      end
    end
  end
end

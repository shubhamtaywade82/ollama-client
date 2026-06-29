# frozen_string_literal: true

require_relative "base"

module Ollama
  module Policies
    # Fallback policy - tries alternative models on failure
    class Fallback < Base
      attr_reader :models, :enabled, :fallback_on, :hooks

      # @param models [Array<String>] Ordered list of models to try
      # @param enabled [Boolean] Whether fallback is enabled (default: true)
      # @param fallback_on [Array<Class>] Exception classes to trigger fallback
      # @param hooks [Hash] Optional hooks: :fallback_triggered, :fallback_succeeded
      def initialize(
        models: [],
        enabled: true,
        fallback_on: [NotFoundError, TimeoutError, HTTPError, UnsupportedCapabilityError],
        hooks: {}
      )
        super()
        @models = Array(models)
        @enabled = enabled
        @fallback_on = fallback_on
        @hooks = hooks
      end

      def call(request, env = {})
        return @app.call(request, env) unless @enabled && !@models.empty?

        current_request = request
        last_error = nil

        @models.each_with_index do |model, index|
          current_request = request_with_model(current_request, model)
          env[:fallback_model] = model
          env[:fallback_index] = index

          begin
            response = @app.call(current_request, env)
            @hooks[:fallback_succeeded]&.call(model, index, env) if index.positive?
            return response
          rescue StandardError => e
            last_error = e
            next unless @fallback_on.any? { |cls| e.is_a?(cls) }
            next unless index < @models.size - 1

            @hooks[:fallback_triggered]&.call(e, model, index, env)
          end
        end

        # All fallbacks exhausted
        raise last_error
      end

      def stream(request, env = {}, &block)
        call(request, env) { |req, env| @app.stream(req, env, &block) }
      end

      private

      def request_with_model(request, model)
        # Create new request with fallback model
        if request.respond_to?(:with_model)
          request.with_model(model)
        else
          # For Request objects, create a new one
          attrs = request.to_h
          attrs[:model] = model
          Request.build(request.endpoint, **attrs)
        end
      end
    end
  end
end

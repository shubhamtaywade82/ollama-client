# frozen_string_literal: true

require_relative "../middleware"

module Ollama
  class Middleware
    # Metrics middleware - collects request/response metrics
    class Metrics < Ollama::Middleware
      attr_reader :collector, :hooks

      def initialize(collector: nil, hooks: {})
        super()
        @collector = collector || default_collector
        @hooks = hooks
      end

      def before_request(request, env)
        @collector.increment(:request_count, tags: { endpoint: request.endpoint })
        @hooks[:before_request]&.call(request, env)
        request
      end

      def after_response(response, env)
        duration = env[:duration_ms]
        endpoint = env[:request]&.endpoint
        success = response.success?

        @collector.increment(:response_count, tags: { endpoint: endpoint, status: response.status.to_s })
        @collector.increment(success ? :success_count : :failure_count, tags: { endpoint: endpoint })
        @collector.timing(:duration_ms, duration, tags: { endpoint: endpoint })

        if env[:request].respond_to?(:prompt_eval_count)
          @collector.increment(:prompt_tokens, env[:request].prompt_eval_count || 0, tags: { endpoint: endpoint })
        end

        if env[:request].respond_to?(:eval_count)
          @collector.increment(:completion_tokens, env[:request].eval_count || 0, tags: { endpoint: endpoint })
        end

        @collector.increment(:stream_count, tags: { endpoint: endpoint }) if env[:request]&.streaming?

        @hooks[:after_response]&.call(response, env)
        response
      end

      def on_error(error, env)
        endpoint = env[:request]&.endpoint
        @collector.increment(:error_count, tags: { endpoint: endpoint, error: error.class.name })
        @hooks[:on_error]&.call(error, env)
        nil
      end

      private

      def default_collector
        # Simple in-memory collector for testing
        Class.new do
          def initialize
            @data = Hash.new { |h, k| h[k] = 0 }
          end

          def increment(metric, value = 1, tags: {})
            key = [metric, tags].hash
            @data[key] += value
          end

          def timing(metric, value, tags: {})
            key = [metric, tags].hash
            @data[key] ||= []
            @data[key] << value
          end

          def get(metric, tags: {})
            @data[[metric, tags].hash]
          end

          def all
            @data
          end
        end.new
      end
    end
  end
end

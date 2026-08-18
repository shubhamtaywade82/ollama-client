# frozen_string_literal: true

require_relative "middleware"

module Ollama
  module Middleware
    # Tracing middleware - adds distributed tracing support
    class Tracing < Ollama::Middleware
      attr_reader :tracer, :service_name

      def initialize(tracer: nil, service_name: "ollama-client")
        super()
        @tracer = tracer || default_tracer
        @service_name = service_name
      end

      def before_request(request, env)
        return request unless @tracer

        span = @tracer.start_span(
          "ollama.request",
          service: @service_name,
          tags: {
            "ollama.endpoint" => request.endpoint,
            "ollama.model" => request.model,
            "ollama.streaming" => request.streaming?.to_s,
            "span.kind" => "client"
          }
        )

        env[:trace_span] = span

        # Inject trace context into headers if tracer supports it
        if @tracer.respond_to?(:inject)
          headers = {}
          @tracer.inject(span.context, headers)
          request = request.with_headers(request.headers.merge(headers))
        end

        request
      end

      def after_response(response, env)
        span = env[:trace_span]
        return response unless span

        span.set_tag("http.status_code", response.status)
        span.set_tag("ollama.success", response.success?.to_s)

        span.set_tag("duration_ms", env[:duration_ms]) if env[:duration_ms]

        span.finish
        env[:trace_span] = nil
        response
      end

      def on_error(error, env)
        span = env[:trace_span]
        return nil unless span

        span.set_tag("error", true)
        span.set_tag("error.type", error.class.name)
        span.set_tag("error.message", error.message)
        span.finish
        env[:trace_span] = nil
        nil
      end

      private

      # No-op tracer by default
      def default_tracer
        Class.new do
          def start_span(*_args, **_kwargs)
            NoOpSpan.new
          end

          def inject(_context, _carrier)
            # no-op
          end
        end.new
      end
    end
  end
end

# No-op span for default tracer
module Ollama
  module Middleware
    module Tracing
      # No-op span implementation used when no tracer is configured
      class NoOpSpan
        def set_tag(*_args); end
        def finish; end

        def context
          NoOpContext.new
        end
      end
    end
  end
end

# No-op context for default tracer
NoOpContext = Class.new

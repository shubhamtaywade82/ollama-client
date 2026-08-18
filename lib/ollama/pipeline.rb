# frozen_string_literal: true

module Ollama
  # Pipeline orchestrates the middleware execution chain.
  # It wraps the transport and applies middleware in order.
  class Pipeline
    attr_reader :transport, :middlewares, :events

    def initialize(transport, middlewares: [], events: nil)
      @transport = transport
      @middlewares = middlewares.dup.freeze
      @events = events || Events.new
    end

    # Add a middleware to the pipeline
    # @param middleware [Class, Ollama::Middleware] Middleware class or instance
    # @param options [Hash] Options to pass to middleware constructor
    # @return [Pipeline] New pipeline with middleware added (immutable)
    def use(middleware, **options)
      middleware_instance = middleware.is_a?(Class) ? middleware.new(**options) : middleware
      raise ArgumentError, "Middleware must be a subclass of Ollama::Middleware" unless middleware_instance.is_a?(Middleware)

      self.class.new(@transport, middlewares: @middlewares + [middleware_instance], events: @events)
    end

    # Execute a request through the pipeline
    # @param request [Ollama::Request] The request to execute
    # @return [Ollama::Transport::Response] The transport response
    def call(request)
      env = { request: request, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      # Execute middleware chain
      execute_chain(request, env)
    end

    # Execute a streaming request through the pipeline
    # @param request [Ollama::Request] The request to execute
    # @yield [chunk] Yields each chunk of the streaming response
    # @return [Ollama::Transport::Response] The final transport response
    def stream(request, &block)
      env = { request: request, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      execute_stream_chain(request, env, &block)
    end

    private

    def execute_chain(request, env)
      # Build the chain from middlewares
      chain = build_chain

      response = nil
      error = nil

      begin
        # Publish before_request event
        @events.publish(:before_request, env)

        # Run before_request hooks
        modified_request = run_before_request_chain(request, env)

        # Execute the transport
        response = chain.call(modified_request, env)

        # Run after_response hooks
        response = run_after_response_chain(response, env)

        # Publish after_response event
        @events.publish(:after_response, env.merge(response: response))
      rescue StandardError => e
        error = e
        fallback = run_on_error_chain(e, env)
        raise e unless fallback

        response = fallback
      ensure
        env[:duration_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - env[:started_at]) * 1000).round(2)
        env[:response] = response
        env[:error] = error
      end

      response
    end

    def execute_stream_chain(request, env)
      # Publish stream_start event
      @events.publish(:stream_start, env)

      modified_request = run_before_request_chain(request, env)

      @transport.stream(uri: modified_request.uri, request: modified_request) do |chunk|
        # Run stream chunk hooks
        chunk = run_stream_chunk_chain(chunk, env)
        @events.publish(:stream_chunk, env.merge(chunk: chunk))

        yield chunk if block_given?
      end
    rescue StandardError => e
      fallback = run_on_error_chain(e, env)
      raise e unless fallback

      fallback
    ensure
      env[:duration_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - env[:started_at]) * 1000).round(2)
      env[:error] = nil
      @events.publish(:stream_end, env)
    end

    def build_chain
      @middlewares.reverse.reduce(@transport) do |app, middleware|
        ChainLink.new(app, middleware)
      end
    end

    def run_before_request_chain(request, env)
      @middlewares.reduce(request) do |req, middleware|
        result = middleware.before_request(req, env)
        result.nil? ? req : result
      end
    end

    def run_after_response_chain(response, env)
      @middlewares.reduce(response) do |resp, middleware|
        result = middleware.after_response(resp, env)
        result.nil? ? resp : result
      end
    end

    def run_on_error_chain(error, env)
      @middlewares.reduce(nil) do |fallback, middleware|
        next fallback if fallback

        result = middleware.on_error(error, env)
        result
      end
    end

    def run_stream_chunk_chain(chunk, env)
      @middlewares.reduce(chunk) do |c, middleware|
        next c unless middleware.respond_to?(:on_stream_chunk)

        result = middleware.on_stream_chunk(c, env)
        result.nil? ? c : result
      end
    end
  end

  # Internal chain link that wraps middleware around transport
  class ChainLink
    def initialize(app, middleware)
      @app = app
      @middleware = middleware
    end

    def call(request, env = {})
      @middleware.around(request, env) { @app.call(request, env) }
    end

    def stream(uri:, request:, &block)
      @app.stream(uri: uri, request: request, &block)
    end
  end
end

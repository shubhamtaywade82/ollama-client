# frozen_string_literal: true

module Ollama
  # Base class for all middleware.
  # Middleware wraps the request/response lifecycle and can modify or observe the flow.
  class Middleware
    # Called before the request is sent to the transport.
    # @param request [Ollama::Request] The request object
    # @param env [Hash] Environment hash passed through the pipeline
    # @return [Ollama::Request, nil] Return a modified request or nil to continue with original
    def before_request(request, _env)
      request
    end

    # Called after the transport returns a response.
    # @param response [Ollama::Transport::Response] The transport response
    # @param env [Hash] Environment hash passed through the pipeline
    # @return [Ollama::Transport::Response, nil] Return a modified response or nil to continue with original
    def after_response(response, _env)
      response
    end

    # Called when an error occurs during request execution.
    # @param error [Exception] The error that was raised
    # @param env [Hash] Environment hash passed through the pipeline
    # @return [Object, nil] Return a fallback response or nil to re-raise the error
    def on_error(_error, _env)
      nil
    end

    # Called around the entire request/response cycle.
    # Use this for timing, logging, metrics, etc.
    # @param request [Ollama::Request] The request object
    # @param env [Hash] Environment hash
    # @yield Execute the next middleware in the chain
    # @return [Object] The result of the block
    def around(_request, _env)
      yield
    end
  end
end

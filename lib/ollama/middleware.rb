# frozen_string_literal: true

module Ollama
  # Base class for middleware.
  class Middleware
    # Called before the request is sent to transport.
    # @param request [Object] request object
    # @param env [Hash] request environment
    # @return [Object, nil] modified request or original
    def before_request(request, _env)
      request
    end

    # Called after transport returns a response.
    # @param response [Object] response object
    # @param env [Hash] request environment
    # @return [Object, nil] modified response or original
    def after_response(response, _env)
      response
    end

    # Called when an error is raised during execution.
    # @param error [Exception] error object
    # @param env [Hash] request environment
    # @return [Object, nil] fallback response or nil to re-raise
    def on_error(_error, _env)
      nil
    end

    # Wraps execution of the next transport or middleware.
    # @param request [Object] request object
    # @param env [Hash] request environment
    # @yield the inner call
    # @return [Object] result of inner call
    def around(_request, _env)
      yield
    end
  end
end

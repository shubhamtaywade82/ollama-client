# frozen_string_literal: true

require "json"
require_relative "../middleware"
require_relative "../transport"

module Ollama
  # Production-behavior middleware policies (retry, timeout, auto-pull, ...).
  #
  # Policies implement Ollama::Middleware's #around(request, env, &block)
  # contract and are attached to a client with:
  #
  #   client.use(Ollama::Policies::Retry, max_attempts: 3)
  #   client.use(Ollama::Policies::Timeout, read_timeout: 30)
  #
  # The chain is assembled by Ollama::Pipeline (see Pipeline::ChainLink):
  # each policy's block is the next link (another policy or the transport).
  #
  # Policies operate on Transport::Request objects (method/uri/headers/body),
  # not the higher-level Ollama::Request, so the shared helpers below derive
  # endpoint/model/body data from the URI and JSON body.
  class Base < Ollama::Middleware
    private

    # Map a transport URI path to a logical endpoint symbol.
    def endpoint(request)
      case request.uri.path
      when "/api/chat" then :chat
      when "/api/generate" then :generate
      when "/api/embed", "/api/embeddings" then :embeddings
      when "/api/show" then :show_model
      when "/api/tags" then :list_models
      when "/api/version" then :version
      when "/api/create" then :create_model
      when "/api/delete" then :delete_model
      when "/api/copy" then :copy_model
      when "/api/pull" then :pull
      when "/api/push" then :push
      when "/api/ps" then :list_running
      end
    end

    # Parse the request JSON body; empty/malformed bodies yield {}.
    def body_hash(request)
      return {} unless request.body.is_a?(String) && !request.body.empty?

      JSON.parse(request.body)
    rescue JSON::ParserError
      {}
    end

    # Model name from the request body, or nil when absent.
    def request_model(request)
      body_hash(request)["model"]
    end

    # New request with the model replaced (used by Fallback).
    def request_with_model(request, model)
      body = body_hash(request).merge("model" => model)
      Transport::Request.new(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        body: JSON.generate(body),
        stream: request.stream,
        timeout: request.timeout
      )
    end
  end
end

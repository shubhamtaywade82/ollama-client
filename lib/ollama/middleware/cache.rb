# frozen_string_literal: true

require_relative "../middleware"

require "digest"

module Ollama
  class Middleware
    # Cache middleware - caches responses based on request key.
    class Cache < ::Ollama::Middleware
      attr_reader :store, :ttl, :key_generator, :cacheable_endpoints

      def initialize(store:, ttl: 300, key_generator: nil,
                     cacheable_endpoints: %i[chat generate embeddings])
        super()
        @store = store
        @ttl = ttl
        @key_generator = key_generator || ->(request) { default_key(request) }
        @cacheable_endpoints = Array(cacheable_endpoints).map(&:to_sym)
      end

      def before_request(request, env)
        return request unless cacheable?(request)

        key = @key_generator.call(request)
        return request unless key

        cached = @store.read(key)
        return request unless cached

        env[:cached_response] = cached
        env[:cache_hit] = true
        request
      end

      def after_response(response, env)
        return response unless cache_write?(env)

        key = @key_generator.call(env[:request])
        return response unless key

        @store.write(key, response, expires_in: @ttl) if response.success?
        response
      end

      private

      def cache_write?(env)
        env[:cacheable] && !env[:cache_hit]
      end

      def cacheable?(request)
        @cacheable_endpoints.include?(request.endpoint.to_sym) &&
          !request.streaming? &&
          request.metadata[:cache] != false
      end

      def default_key(request)
        parts = [
          request.endpoint,
          request.model,
          request.messages&.hash,
          request.prompt&.hash,
          request.tools&.hash,
          request.schema&.hash,
          request.options&.hash
        ].compact

        Digest::SHA256.hexdigest(parts.join("|"))
      end
    end
  end
end

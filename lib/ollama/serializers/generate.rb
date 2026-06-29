# frozen_string_literal: true

require_relative "base"

module Ollama
  module Serializers
    # Serializes generate completion requests
    class Generate < Base
      def call(request)
        body = build_generate_body(request)
        Transport::Request.new(
          method: http_method(request),
          uri: build_uri(request, request.path),
          headers: build_headers(request),
          body: body.to_json,
          stream: request.streaming?,
          timeout: request.metadata[:timeout] || 120
        )
      end

      private

      def build_generate_body(request)
        body = {
          model: request.model,
          prompt: request.prompt,
          stream: request.streaming?
        }

        body[:format] = request.schema if request.schema
        body[:keep_alive] = request.keep_alive if request.keep_alive
        body[:think] = request.think unless request.think.nil?
        body[:images] = request.images if request.images
        body[:options] = request.options if request.options&.any?

        # Handle raw_options
        if request.raw_options
          body[:system] = request.raw_options[:system] if request.raw_options[:system]
          body[:suffix] = request.raw_options[:suffix] if request.raw_options[:suffix]
          body[:raw] = request.raw_options[:raw] if request.raw_options[:raw]
        end

        body.compact
      end

      def build_uri(request, base_path)
        request.metadata[:uri] || URI.join(request.metadata[:base_url] || "http://localhost:11434", base_path)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base"

module Ollama
  module Serializers
    # Serializes generate completion requests
    class Generate < Base
      RAW_KEYS = %i[system suffix raw context template logprobs top_logprobs].freeze
      private_constant :RAW_KEYS

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

        body[:tools] = request.tools if request.tools
        format_val = request.format || request.schema
        body[:format] = format_val if format_val
        body[:keep_alive] = request.keep_alive if request.keep_alive
        body[:think] = request.think unless request.think.nil?
        body[:images] = request.images if request.images
        body[:options] = request.options if request.options&.any?
        merge_raw_options(body, request.raw_options)

        body.compact
      end

      def merge_raw_options(body, raw)
        return unless raw

        RAW_KEYS.each { |key| body[key] = raw[key] unless raw[key].nil? }
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base"

module Ollama
  module Serializers
    # Serializes chat completion requests
    class Chat < Base
      def call(request)
        body = build_chat_body(request)
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

      def build_chat_body(request)
        body = {
          model: request.model,
          messages: request.messages,
          stream: request.streaming?
        }

        body[:tools] = request.tools if request.tools
        body[:format] = request.format if request.format
        body[:think] = request.think unless request.think.nil?
        body[:keep_alive] = request.keep_alive if request.keep_alive
        body[:options] = request.options if request.options&.any?
        body[:logprobs] = request.raw_options[:logprobs] if request.raw_options&.dig(:logprobs)
        body[:top_logprobs] = request.raw_options[:top_logprobs] if request.raw_options&.dig(:top_logprobs)

        body.compact
      end

      def build_uri(request, base_path)
        request.metadata[:uri] || URI.join(request.metadata[:base_url] || "http://localhost:11434", base_path)
      end
    end
  end
end

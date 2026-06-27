# frozen_string_literal: true

require "uri"

module Ollama
  module Providers
    # OpenAI-compatible API provider (e.g. llama.cpp, vLLM, OpenAI)
    class OpenAI < Base
      def chat_endpoint
        path = config.base_url.end_with?("/") ? "chat/completions" : "/chat/completions"
        URI("#{config.base_url}#{path}")
      end

      def generate_endpoint
        path = config.base_url.end_with?("/") ? "completions" : "/completions"
        URI("#{config.base_url}#{path}")
      end

      def embeddings_endpoint
        path = config.base_url.end_with?("/") ? "embeddings" : "/embeddings"
        URI("#{config.base_url}#{path}")
      end

      def models_endpoint
        path = config.base_url.end_with?("/") ? "models" : "/models"
        URI("#{config.base_url}#{path}")
      end

      def format_chat_request(params)
        # Flatten options for OpenAI
        options = params.delete(:options) || {}
        params[:temperature] = options[:temperature] if options[:temperature]
        params[:top_p] = options[:top_p] if options[:top_p]
        params[:max_tokens] = options[:num_ctx] if options[:num_ctx]

        # Ollama 'format' can be 'json' or a schema.
        # OpenAI uses 'response_format'
        format = params.delete(:format)
        if format == "json"
          params[:response_format] = { type: "json_object" }
        elsif format.is_a?(Hash)
          params[:response_format] = { type: "json_schema", json_schema: format }
        end

        params
      end

      def format_generate_request(params)
        # OpenAI completions API is similar to chat but uses 'prompt'
        format_chat_request(params)
      end

      def format_embeddings_request(params)
        params
      end

      def normalize_chat_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("choices")

        # Translate OpenAI format to Ollama format for Ollama::Response
        choice = response_data["choices"][0]
        message = choice["message"]

        {
          "model" => response_data["model"],
          "message" => {
            "role" => message["role"],
            "content" => message["content"],
            "tool_calls" => translate_tool_calls(message["tool_calls"])
          },
          "done" => choice["finish_reason"] == "stop",
          "done_reason" => choice["finish_reason"],
          "usage" => response_data["usage"]
        }
      end

      def normalize_generate_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("choices")

        choice = response_data["choices"][0]
        {
          "model" => response_data["model"],
          "response" => choice["text"],
          "done" => choice["finish_reason"] == "stop",
          "usage" => response_data["usage"]
        }
      end

      def normalize_embeddings_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("data")

        # OpenAI format: {"data": [{"embedding": [...]}, ...]}
        # Ollama format: {"embeddings": [[...], ...]}
        {
          "model" => response_data["model"],
          "embeddings" => response_data["data"].map { |d| d["embedding"] }
        }
      end

      def normalize_models_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("data")

        # OpenAI format: {"data": [{"id": "model-name", ...}, ...]}
        # Ollama format: {"models": [{"name": "model-name", ...}, ...]}
        {
          "models" => response_data["data"].map do |m|
            {
              "name" => m["id"],
              "model" => m["id"],
              "details" => { "family" => m["owned_by"] }
            }
          end
        }
      end

      private

      def translate_tool_calls(openai_tool_calls)
        return nil unless openai_tool_calls

        openai_tool_calls.map do |tc|
          {
            "id" => tc["id"] || tc[:id] || "call_#{tc.dig("function", "name")}_#{object_id}",
            "type" => tc["type"] || tc[:type] || "function",
            "function" => {
              "name" => tc.dig("function", "name"),
              "arguments" => tc.dig("function", "arguments")
            }
          }
        end
      end
    end
  end
end

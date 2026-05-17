# frozen_string_literal: true

require "uri"

module Ollama
  module Providers
    # Provider for llama.cpp server (native API).
    # Supports native /completion and GBNF grammars.
    class LlamaCpp < Base
      def chat_endpoint
        URI("#{config.base_url}/v1/chat/completions")
      end

      def generate_endpoint
        URI("#{config.base_url}/completion")
      end

      def embeddings_endpoint
        URI("#{config.base_url}/embedding")
      end

      def models_endpoint
        URI("#{config.base_url}/v1/models")
      end

      def format_chat_request(params)
        # Use OpenAI compatible endpoint for chat
        options = params.delete(:options) || {}
        params[:temperature] = options[:temperature] if options[:temperature]
        params[:top_p] = options[:top_p] if options[:top_p]
        params[:max_tokens] = options[:num_predict] if options[:num_predict]

        format = params.delete(:format)
        if format == "json"
          params[:response_format] = { type: "json_object" }
        elsif format.is_a?(Hash)
          params[:response_format] = { type: "json_schema", json_schema: format }
        end

        params
      end

      def format_generate_request(params)
        # Use native /completion format
        options = params.delete(:options) || {}
        {
          prompt: params[:prompt],
          temperature: options[:temperature] || config.temperature,
          top_p: options[:top_p] || config.top_p,
          n_predict: options[:num_predict] || 128,
          stream: params[:stream] || false,
          stop: options[:stop] || [],
          grammar: params[:format].is_a?(String) && params[:format].match?(/root\s*::=/) ? params[:format] : nil
        }.compact
      end

      def format_embeddings_request(params)
        { content: params[:input] }
      end

      def normalize_chat_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("choices")

        choice = response_data["choices"][0]
        message = choice["message"]

        {
          "model" => response_data["model"],
          "message" => {
            "role" => message["role"],
            "content" => message["content"],
            "tool_calls" => translate_tool_calls(message["tool_calls"])
          },
          "done" => !choice["finish_reason"].nil?,
          "done_reason" => choice["finish_reason"],
          "usage" => response_data["usage"]
        }
      end

      private

      def translate_tool_calls(openai_tool_calls)
        return nil unless openai_tool_calls

        openai_tool_calls.map do |tc|
          {
            "id" => tc["id"] || tc[:id] || "call_#{tc.dig('function', 'name')}_#{object_id}",
            "type" => tc["type"] || tc[:type] || "function",
            "function" => {
              "name" => tc.dig("function", "name"),
              "arguments" => tc.dig("function", "arguments")
            }
          }
        end
      end



      def normalize_generate_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("content")

        {
          "model" => "llama.cpp",
          "response" => response_data["content"],
          "done" => response_data["stop"] == true,
          "usage" => {
            "prompt_eval_count" => response_data["tokens_evaluated"],
            "eval_count" => response_data["tokens_predicted"]
          }
        }
      end

      def normalize_embeddings_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("embedding")

        {
          "model" => "llama.cpp",
          "embeddings" => [response_data["embedding"]]
        }
      end

      def normalize_models_response(response_data)
        return response_data unless response_data.is_a?(Hash) && response_data.key?("data")

        {
          "models" => response_data["data"].map do |m|
            { "name" => m["id"], "details" => { "family" => "llama" } }
          end
        }
      end
    end
  end
end

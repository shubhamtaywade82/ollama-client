# frozen_string_literal: true

require "securerandom"

module Ollama
  class Client
    # Optional OpenAI-style compatibility facade.
    module OpenAICompat
      # Entry point for OpenAI-compatible sub-APIs.
      # @return [OpenAIAdapter]
      def openai
        @openai ||= OpenAIAdapter.new(self)
      end

      # Entry point object for OpenAI-compatible sub-APIs.
      class OpenAIAdapter
        # @param client [Ollama::Client]
        def initialize(client)
          @client = client
          @config = client.instance_variable_get(:@config)
        end

        # @return [ModelsAdapter]
        def models
          ModelsAdapter.new(@client, @config)
        end

        # @return [EmbeddingsAdapter]
        def embeddings
          EmbeddingsAdapter.new(@client)
        end

        # @return [ChatAdapter]
        def chat
          ChatAdapter.new(@client)
        end

        # @return [CompletionsAdapter]
        def completions
          CompletionsAdapter.new(@client)
        end
      end

      # Adapter for OpenAI-like models listing.
      class ModelsAdapter
        # @param client [Ollama::Client]
        # @param config [Ollama::Config]
        def initialize(client, config)
          @client = client
          @config = config
        end

        # List models in OpenAI-compatible format.
        # @return [Hash] OpenAI-style list response
        def list
          models = @client.list_models || []
          {
            "object" => "list",
            "data" => models.map do |m|
              {
                "id" => m["name"],
                "object" => "model",
                "created" => Time.now.to_i,
                "owned_by" => "ollama"
              }
            end
          }
        end
      end

      # Adapter for OpenAI-like embeddings create API.
      class EmbeddingsAdapter
        # @param client [Ollama::Client]
        def initialize(client)
          @client = client
        end

        # Create embeddings in OpenAI-compatible format.
        # @param model [String]
        # @param input [String, Array<String>]
        # @param opts [Hash] additional options
        # @return [Hash] OpenAI-style embeddings response
        def create(model:, input:, **opts)
          vectors = @client.embeddings.embed(model: model, input: input, **opts)
          vectors = [vectors] unless input.is_a?(Array)
          {
            "object" => "list",
            "data" => vectors.each_with_index.map do |emb, i|
              { "object" => "embedding", "embedding" => emb, "index" => i }
            end,
            "model" => model
          }
        end
      end

      # Adapter for OpenAI-like chat/completions API.
      class ChatAdapter
        # @param client [Ollama::Client]
        def initialize(client)
          @client = client
        end

        # @return [self]
        def completions
          self
        end

        # Create chat completion in OpenAI-compatible format.
        # @param model [String]
        # @param messages [Array<Hash>]
        # @param tools [Array<Hash>, nil]
        # @param temperature [Float, nil]
        # @param top_p [Float, nil]
        # @return [Hash] OpenAI-style chat completion response
        def create(model:, messages:, tools: nil, temperature: nil, top_p: nil, **)
          response = @client.chat(
            model: model,
            messages: messages,
            tools: tools,
            options: { temperature: temperature, top_p: top_p }.compact
          )

          {
            "id" => "chatcmpl-#{SecureRandom.hex(12)}",
            "object" => "chat.completion",
            "created" => Time.now.to_i,
            "model" => model,
            "choices" => [
              {
                "index" => 0,
                "message" => {
                  "role" => "assistant",
                  "content" => response.message.content,
                  "tool_calls" => openai_tool_calls(response)
                },
                "finish_reason" => response.done_reason || "stop"
              }
            ]
          }
        end

        private

        # @param response [Ollama::Response]
        # @return [Array<Hash>, nil]
        def openai_tool_calls(response)
          response.message.tool_calls&.map do |tc|
            {
              "type" => "function",
              "function" => {
                "name" => tc.name,
                "arguments" => tc.arguments.to_json
              }
            }
          end
        end
      end

      # Adapter for OpenAI-like text completions API.
      class CompletionsAdapter
        # @param client [Ollama::Client]
        def initialize(client)
          @client = client
        end

        # Create text completion in OpenAI-compatible format.
        # @param model [String]
        # @param prompt [String]
        # @param temperature [Float, nil]
        # @param top_p [Float, nil]
        # @return [Hash] OpenAI-style text completion response
        def create(model:, prompt:, temperature: nil, top_p: nil, **)
          text = @client.generate(model: model, prompt: prompt, options: { temperature: temperature, top_p: top_p }.compact)
          {
            "id" => "cmpl-#{SecureRandom.hex(12)}",
            "object" => "text_completion",
            "created" => Time.now.to_i,
            "model" => model,
            "choices" => [{ "index" => 0, "text" => text, "finish_reason" => "stop" }]
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "securerandom"

module Ollama
  class Client
    # Optional OpenAI-style compatibility facade.
    module OpenAICompat
      def openai
        @openai ||= OpenAIAdapter.new(self)
      end

      # Entry point object for OpenAI-compatible sub-APIs.
      class OpenAIAdapter
        def initialize(client)
          @client = client
          @config = client.instance_variable_get(:@config)
        end

        def models
          ModelsAdapter.new(@client, @config)
        end

        def embeddings
          EmbeddingsAdapter.new(@client)
        end

        def chat
          ChatAdapter.new(@client)
        end

        def completions
          CompletionsAdapter.new(@client)
        end
      end

      # Adapter for OpenAI-like models listing.
      class ModelsAdapter
        def initialize(client, config)
          @client = client
          @config = config
        end

        def list
          tags = @client.tags["models"] || []
          {
            "object" => "list",
            "data" => tags.map do |m|
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
        def initialize(client)
          @client = client
        end

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
        def initialize(client)
          @client = client
        end

        def completions
          self
        end

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
      end

      # Adapter for OpenAI-like text completions API.
      class CompletionsAdapter
        def initialize(client)
          @client = client
        end

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

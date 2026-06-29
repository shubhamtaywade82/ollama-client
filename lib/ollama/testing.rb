# frozen_string_literal: true

require "time"

module Ollama
  # Testing support module for stubbing Ollama client responses in specs
  module Testing
    class << self
      attr_reader :stubbed_responses

      def enqueue_stub(type, data)
        @stubbed_responses ||= []
        @stubbed_responses << { type: type, data: data }
      end

      def pop_stub(type)
        @stubbed_responses ||= []
        idx = @stubbed_responses.find_index { |s| s[:type] == type }
        return unless idx

        @stubbed_responses.delete_at(idx)[:data]
      end

      def clear!
        @stubbed_responses = []
      end
    end

    # Client extension to intercept requests and return stubbed responses during testing
    module ClientExtension
      def chat(messages:, **args)
        stub = Ollama::Testing.pop_stub(:chat)
        return super if stub.nil?

        if args[:hooks] && stub["stream_chunks"]
          stub["stream_chunks"].each do |chunk|
            args[:hooks][:on_token]&.call(chunk)
          end
        end

        Response.new(stub)
      end

      def generate(prompt:, **args)
        stub = Ollama::Testing.pop_stub(:generate)
        return super if stub.nil?

        if args[:hooks] && stub["stream_chunks"]
          stub["stream_chunks"].each do |chunk|
            args[:hooks][:on_token]&.call(chunk)
          end
        end

        # When a schema is specified, generate returns a parsed Hash
        if args[:schema] && stub["response"].is_a?(String)
          begin
            JSON.parse(stub["response"])
          rescue JSON::ParserError
            stub["response"]
          end
        else
          stub["response"]
        end
      end
    end

    def stub_ollama_chat(content:, model: nil, role: "assistant", done: true, done_reason: "stop", extra: {})
      Ollama::Testing.enqueue_stub(:chat, {
        "model" => model || Ollama.config.model,
        "created_at" => Time.now.utc.iso8601,
        "message" => {
          "role" => role,
          "content" => content
        },
        "done" => done,
        "done_reason" => done_reason
      }.merge(stringify_keys(extra)))
    end

    def stub_ollama_generate(content:, model: nil, done: true, extra: {})
      Ollama::Testing.enqueue_stub(:generate, {
        "model" => model || Ollama.config.model,
        "created_at" => Time.now.utc.iso8601,
        "response" => content,
        "done" => done
      }.merge(stringify_keys(extra)))
    end

    def clear_ollama_stubs
      Ollama::Testing.clear!
    end

    private

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end
  end
end

Ollama::Client.prepend(Ollama::Testing::ClientExtension) if defined?(Ollama::Client)

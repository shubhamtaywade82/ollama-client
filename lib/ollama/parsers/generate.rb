# frozen_string_literal: true

require_relative "base"
require_relative "../responses/generate"

module Ollama
  module Parsers
    # Parses generate completion responses
    class Generate < Base
      def initialize(provider: nil)
        super()
        @provider = provider
      end

      def call(transport_response)
        data = json(transport_response)
        data = @provider.normalize_generate_response(data) if @provider.respond_to?(:normalize_generate_response)
        # Generate endpoint returns a flat response with "response" field
        # Convert to Response-compatible format
        response_data = {
          "message" => { "role" => "assistant", "content" => data["response"] },
          "done" => data["done"],
          "done_reason" => data["done_reason"],
          "model" => data["model"],
          "created_at" => data["created_at"],
          "total_duration" => data["total_duration"],
          "load_duration" => data["load_duration"],
          "prompt_eval_count" => data["prompt_eval_count"],
          "prompt_eval_duration" => data["prompt_eval_duration"],
          "eval_count" => data["eval_count"],
          "eval_duration" => data["eval_duration"],
          "context" => data["context"]
        }
        Responses::Generate.new(response_data)
      end
    end
  end
end

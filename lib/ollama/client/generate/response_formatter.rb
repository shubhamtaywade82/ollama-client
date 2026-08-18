# frozen_string_literal: true

require_relative "../../json_fragment_extractor"
require_relative "../../schema_validator"
require_relative "../../errors"

module Ollama
  class Client
    module Generate
      # Handles parsing, validation, and structured output formatting for generate responses
      class ResponseFormatter
        def initialize(provider:, config:, schema_cache: {})
          @provider = provider
          @config = config
          @schema_cache = schema_cache
        end

        def process(raw_response, schema, think, return_reasoning)
          if think && return_reasoning
            extract_reasoning(raw_response, schema)
          elsif schema
            parsed = parse_json_response(raw_response)
            SchemaValidator.validate!(parsed, schema)
            parsed
          else
            raw_response
          end
        end

        def format(response_data, context, return_meta, model, attempts, started_at)
          return response_data unless return_meta

          {
            "data" => response_data,
            "context" => context,
            "meta" => {
              "endpoint" => @provider.generate_endpoint.path,
              "model" => model || @config.model,
              "attempts" => attempts,
              "latency_ms" => elapsed_ms(started_at)
            }
          }
        end

        def extract_reasoning(raw_text, user_schema)
          reasoning = ""
          final_output = raw_text

          if raw_text.match?(%r{思考(.*?)</think>}mi)
            reasoning = raw_text.match(%r{思考(.*?)</think>}mi)[1].strip
            final_output = raw_text.sub(%r{思考.*?</think>}mi, "").strip
          elsif raw_text.match?(/思考(.*?)回答/mi)
            reasoning = raw_text.match(/思考(.*?)回答/mi)[1].strip
            final_output = raw_text.sub(/思考.*?回答/mi, "").strip
          elsif raw_text.include?("回答")
            parts = raw_text.split("回答", 2)
            reasoning = parts[0].sub("思考", "").strip
            final_output = parts[1].strip
          elsif raw_text.match?(%r{<think>(.*?)</think>}mi)
            reasoning = raw_text.match(%r{<think>(.*?)</think>}mi)[1].strip
            final_output = raw_text.sub(%r{<think>.*?</think>}mi, "").strip
          elsif raw_text.include?("\n")
            parts = raw_text.split("\n", 2)
            reasoning = parts[0].strip
            final_output = parts[1].strip
          end

          if user_schema
            parsed_final = parse_json_response(final_output)
            SchemaValidator.validate!(parsed_final, user_schema)
            final_output = parsed_final
          end

          {
            "reasoning" => reasoning,
            "final" => final_output
          }
        end

        def parse_json_response(raw)
          json_text = JsonFragmentExtractor.call(raw)
          JSON.parse(json_text)
        rescue JSON::ParserError => e
          raise InvalidJSONError, "Failed to parse extracted JSON: #{e.message}. Extracted: #{json_text&.slice(0, 200)}..."
        end

        private

        def elapsed_ms(started_at)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(1)
        end
      end
    end
  end
end

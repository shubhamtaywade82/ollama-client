# frozen_string_literal: true

require_relative "base"
require "json"

module Ollama
  module Policies
    # SchemaRepair policy - validates and repairs LLM output against a schema
    class SchemaRepair < Base
      attr_reader :max_repairs, :strict, :hooks

      # @param max_repairs [Integer] Maximum number of repair attempts (default: 2)
      # @param strict [Boolean] Whether to use strict schema validation (default: true)
      # @param hooks [Hash] Optional hooks: :before_repair, :after_repair, :schema_violation
      def initialize(max_repairs: 2, strict: true, hooks: {})
        super()
        @max_repairs = max_repairs
        @strict = strict
        @hooks = hooks
      end

      def call(request, env = {})
        response = @app.call(request, env)

        # Only validate/repair if schema is provided
        schema = request.raw_options&.dig(:schema) || request.raw_options&.dig(:format)
        return response unless schema

        attempt = 0
        current_response = response

        loop do
          attempt += 1
          env[:schema_repair_attempt] = attempt

          parsed = parse_body(current_response)
          return current_response unless parsed

          begin
            validate_schema(parsed, schema)
            return current_response
          rescue SchemaViolationError => e
            @hooks[:schema_violation]&.call(e, env)

            raise e if attempt >= @max_repairs

            @hooks[:before_repair]&.call(parsed, e, env)

            repaired = repair_output(parsed, schema, e)

            raise e unless repaired

            @hooks[:after_repair]&.call(repaired, env)
            current_response = create_repaired_response(current_response, repaired)
          end
        end
      end

      def stream(request, env = {}, &block)
        @app.stream(request, env, &block)
      end

      private

      def parse_body(response)
        return nil unless response&.body

        body = response.body
        case body
        when String
          JSON.parse(body)
        when Hash, Array
          body
        end
      rescue JSON::ParserError
        nil
      end

      def validate_schema(data, schema)
        # Use existing schema validator
        require_relative "../schema_validator"
        Ollama::SchemaValidator.validate!(data, schema)
      end

      def repair_output(data, schema, error)
        # Try to repair based on violation type
        violations = error.violations
        return nil unless violations

        repaired = data.dup

        violations.each do |violation|
          case violation[:type]
          when :missing_required_field
            field = violation[:field]
            default = default_for_schema_field(schema, field)
            repaired[field] = default if default
          when :type_mismatch
            field = violation[:field]
            expected = violation[:expected]
            repaired[field] = coerce_type(repaired[field], expected)
          when :additional_properties
            field = violation[:field]
            repaired.delete(field) if @strict
          when :pattern_mismatch
            field = violation[:field]
            repaired[field] = "" # Clear invalid value
          end
        end

        # Validate repaired output
        validate_schema(repaired, schema)
        repaired
      rescue StandardError
        nil
      end

      def default_for_schema_field(schema, field)
        return nil unless schema.is_a?(Hash)

        properties = schema["properties"] || schema[:properties]
        return nil unless properties

        prop = properties[field] || properties[field.to_sym]
        return nil unless prop

        case prop["type"] || prop[:type]
        when "string" then ""
        when "number", "integer" then 0
        when "boolean" then false
        when "array" then []
        when "object" then {}
        end
      end

      def coerce_type(value, expected_type)
        return value if value.nil?

        case expected_type.to_s
        when "string" then value.to_s
        when "number", "integer" then value.to_f
        when "boolean" then value.to_s.downcase == "true"
        when "array" then Array(value)
        when "object" then value.is_a?(Hash) ? value : {}
        else value
        end
      end

      def create_repaired_response(original_response, repaired_data)
        original_response.class.new(
          status: original_response.status,
          headers: original_response.headers,
          body: JSON.generate(repaired_data),
          raw: original_response.raw,
          duration_ms: original_response.duration_ms
        )
      end
    end
  end
end

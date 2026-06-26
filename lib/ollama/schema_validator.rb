# frozen_string_literal: true

require "json"

module Ollama
  # JSON schema validation for structured output.
  class SchemaValidator
    class SchemaViolationError < Error; end

    # @param data [Hash]
    # @param schema [Hash]
    # @raise [SchemaViolationError]
    def self.validate!(data, schema)
      return data unless schema.is_a?(Hash)

      StrictSchema.new(schema).call!(data)
      data
    rescue JSON::ParserError => e
      raise SchemaViolationError, "Invalid schema: #{e.message}"
    end

    # Internal strict JSON Schema validator.
    class StrictSchema
      REQUIRED_KEY = "required".freeze
      PROPERTIES_KEY = "properties".freeze
      TYPE_KEY = "type".freeze
      ADDITIONAL_PROPERTIES_KEY = "additionalProperties".freeze

      def initialize(schema)
        @schema = schema
      end

      def call!(data)
        type = data_type(data)
        return if type_matches?(data, @schema[TYPE_KEY])

        raise SchemaViolationError, "Type mismatch, expected #{@schema[TYPE_KEY] || 'any'} got #{type}"
      end

      private

      def data_type(data)
        case data
        when Hash then "object"
        when Array then "array"
        when String then "string"
        when Numeric then "number"
        when true, false then "boolean"
        else "null"
        end
      end

      def type_matches?(data, expected)
        return true if expected.nil?

        case expected
        when "object" then data.is_a?(Hash)
        when "array" then data.is_a?(Array)
        when "string" then data.is_a?(String)
        when "number" then data.is_a?(Numeric)
        when "boolean" then data.is_a?(TrueClass) || data.is_a?(FalseClass)
        when "null" then data.nil?
        else true
        end
      end
    end
  end
end

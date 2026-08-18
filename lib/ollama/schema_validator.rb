# frozen_string_literal: true

require "json"

module Ollama
  # JSON schema validation for structured output.
  class SchemaValidator
    # @param data [Hash]
    # @param schema [Hash]
    # @raise [SchemaViolationError]
    def self.validate!(data, schema)
      return data unless schema.is_a?(Hash)
      return data if schema.empty?

      new(schema).validate!(data)
    rescue JSON::ParserError => e
      raise SchemaViolationError, "Invalid schema: #{e.message}"
    end

    def initialize(schema)
      @required = Array(schema["required"])
      @properties = schema["properties"] || {}
      @additional_properties = schema.fetch("additionalProperties", false)
      @type = schema["type"]
    end

    def validate!(data)
      raise SchemaViolationError, "Expected object, got #{data.class}" unless data.is_a?(Hash)
      raise SchemaViolationError, "Expected hash, got nil" if data.nil?

      check_additional_properties!(data)
      check_required!(data)
      check_property_types!(data)

      data
    end

    private

    def check_additional_properties!(data)
      return unless @additional_properties == false

      extra = data.keys - @properties.keys
      return if extra.empty?

      raise SchemaViolationError.new(
        "Additional properties not allowed: #{extra.join(", ")}",
        violations: extra.map { |key| { type: :additional_properties, field: key } }
      )
    end

    def check_required!(data)
      required_missing = @required.reject { |key| data.key?(key) }
      return if required_missing.empty?

      raise SchemaViolationError.new(
        "Required properties missing: #{required_missing.join(", ")}",
        violations: required_missing.map { |key| { type: :missing_required_field, field: key } }
      )
    end

    def check_property_types!(data)
      data.each do |key, value|
        expected = @properties[key]
        if expected.nil? && @additional_properties == false
          raise SchemaViolationError.new(
            "Unexpected property: #{key}",
            violations: [{ type: :additional_properties, field: key }]
          )
        end

        next unless expected.is_a?(Hash)

        expected_type = expected["type"]
        next unless expected_type

        actual_type = type_name(value)
        next if type_matches?(actual_type, expected_type)

        raise SchemaViolationError.new(
          "Type mismatch for #{key}: expected #{expected_type}, got #{actual_type}",
          violations: [{ type: :type_mismatch, field: key, expected: expected_type }]
        )
      end
    end

    def type_name(value)
      case value
      when Hash then "object"
      when Array then "array"
      when String then "string"
      when Numeric then "number"
      when true, false then "boolean"
      when nil then "null"
      else value.class.name
      end
    end

    def type_matches?(actual, expected)
      return true if expected.nil?
      return true if expected == "any"

      case expected
      when "object" then actual == "object"
      when "array" then actual == "array"
      when "string" then actual == "string"
      when "integer" then %w[integer number].include?(actual)
      when "number" then %w[integer number float].include?(actual)
      when "boolean" then actual == "boolean"
      when "null" then actual == "null"
      else
        actual == expected
      end
    end
  end
end

# frozen_string_literal: true

require "json-schema"
require_relative "errors"

module Ollama
  # Validates JSON data against JSON Schema
  #
  # For agent-grade usage, enforces strict schemas by default:
  # - additionalProperties: false (unless explicitly set)
  # - Prevents LLMs from adding unexpected fields
  class SchemaValidator
    def self.validate!(data, schema)
      JSON::Validator.validate!(prepare_schema(schema), data)
    rescue JSON::Schema::ValidationError => e
      raise SchemaViolationError, e.message
    end

    # JSON Schema defaults to allowing additional properties unless
    # `additionalProperties: false` is specified. For agent-grade contracts,
    # we want the stricter default, while still allowing callers to override
    # it explicitly on any object schema.
    def self.prepare_schema(schema)
      enforce_no_additional_properties(schema)
    end

    def self.enforce_no_additional_properties(node)
      case node
      when Array
        node.map { |v| enforce_no_additional_properties(v) }
      when Hash
        h = node.dup

        # Recurse into common schema composition keywords
        %w[anyOf oneOf allOf].each do |k|
          h[k] = h[k].map { |v| enforce_no_additional_properties(v) } if h[k].is_a?(Array)
        end

        # Recurse into nested schemas
        h["not"] = enforce_no_additional_properties(h["not"]) if h["not"].is_a?(Hash)

        if h["properties"].is_a?(Hash)
          h["properties"] = h["properties"].transform_values { |v| enforce_no_additional_properties(v) }
        end

        if h["patternProperties"].is_a?(Hash)
          h["patternProperties"] = h["patternProperties"].transform_values { |v| enforce_no_additional_properties(v) }
        end

        if h["items"]
          h["items"] = enforce_no_additional_properties(h["items"])
        end

        if h["additionalItems"]
          h["additionalItems"] = enforce_no_additional_properties(h["additionalItems"])
        end

        # JSON Schema draft variants
        if h["definitions"].is_a?(Hash)
          h["definitions"] = h["definitions"].transform_values { |v| enforce_no_additional_properties(v) }
        end

        if h["$defs"].is_a?(Hash)
          h["$defs"] = h["$defs"].transform_values { |v| enforce_no_additional_properties(v) }
        end

        # Enforce strict object shape by default.
        is_objectish =
          h["type"] == "object" ||
          h.key?("properties") ||
          h.key?("patternProperties")

        if is_objectish && !h.key?("additionalProperties")
          h["additionalProperties"] = false
        end

        h
      else
        node
      end
    end

    private_class_method :prepare_schema, :enforce_no_additional_properties
  end
end

# frozen_string_literal: true

require "json-schema"
require_relative "errors"

module Ollama
  class SchemaValidator
    def self.validate!(data, schema)
      JSON::Validator.validate!(schema, data)
    rescue JSON::Schema::ValidationError => e
      raise SchemaViolationError, e.message
    end
  end
end


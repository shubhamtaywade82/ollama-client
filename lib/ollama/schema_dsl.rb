# frozen_string_literal: true

module Ollama
  # Tiny Ruby DSL for JSON Schema objects.
  #
  # This is additive only: it produces schema hashes accepted by the existing
  # `Client.generate(schema:)` and `Client.chat(format:)` paths.
  #
  # Example:
  #
  #   schema = Ollama::SchemaDSL.define do
  #     string :direction, enum: %w[buy sell wait]
  #     number :confidence, minimum: 0, maximum: 1
  #   end.to_h
  #
  #   client.generate(prompt: "...", schema: schema)
  class SchemaDSL
    attr_reader :properties, :required

    def initialize
      @properties = {}
      @required = []
    end

    def self.define(&block)
      instance = new
      instance.instance_eval(&block)
      instance
    end

    def string(name, enum: nil, optional: false, default: nil, description: nil)
      add_property(name, "string", enum: enum, optional: optional, default: default, description: description)
    end

    def number(name, minimum: nil, maximum: nil, optional: false, default: nil, description: nil)
      add_property(name, "number", minimum: minimum, maximum: maximum, optional: optional, default: default,
        description: description)
    end

    def integer(name, minimum: nil, maximum: nil, optional: false, default: nil, description: nil)
      add_property(name, "integer", minimum: minimum, maximum: maximum, optional: optional, default: default,
        description: description)
    end

    def boolean(name, optional: false, default: nil, description: nil)
      add_property(name, "boolean", optional: optional, default: default, description: description)
    end

    def array(name, items: nil, optional: false, default: nil, description: nil)
      prop = { "type" => "array" }
      prop["items"] = items if items
      add_property_entry(name, prop, optional: optional, default: default, description: description)
    end

    def object(name, properties: {}, optional: false, default: nil, description: nil)
      prop = { "type" => "object", "properties" => properties }
      add_property_entry(name, prop, optional: optional, default: default, description: description)
    end

    def to_h
      schema = {
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => false
      }
      schema.delete("required") if required.empty?
      schema
    end

    private

    def add_property(name, type, enum: nil, optional: false, default: nil, description: nil, minimum: nil, maximum: nil)
      prop = { "type" => type }
      prop["enum"] = Array(enum) if enum
      prop["description"] = description if description
      prop["minimum"] = minimum unless minimum.nil?
      prop["maximum"] = maximum unless maximum.nil?
      add_property_entry(name, prop, optional: optional, default: default)
    end

    def add_property_entry(name, prop, optional: false, default: nil, description: nil)
      @properties[name.to_s] = prop
      @required << name.to_s unless optional
      prop["default"] = default if default
      prop["description"] = description if description
    end
  end
end

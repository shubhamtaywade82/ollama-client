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
  class SchemaDSL
    attr_reader :properties, :required

    def initialize
      @properties = {}
      @required = []
    end

    def self.define(&)
      instance = new
      instance.instance_eval(&)
      instance
    end

    def string(name, enum: nil, optional: false, default: nil, description: nil)
      add_property(name, "string", enum: enum, optional: optional, default: default, description: description)
    end

    def number(name, minimum: nil, maximum: nil, optional: false, default: nil, description: nil)
      add_property(
        name, "number",
        minimum: minimum, maximum: maximum, optional: optional,
        default: default, description: description
      )
    end

    def integer(name, minimum: nil, maximum: nil, optional: false, default: nil, description: nil)
      add_property(
        name, "integer",
        minimum: minimum, maximum: maximum, optional: optional,
        default: default, description: description
      )
    end

    def boolean(name, optional: false, default: nil, description: nil)
      add_property(name, "boolean", optional: optional, default: default, description: description)
    end

    def array(name, items: nil, of: nil, optional: false, default: nil, description: nil, &block)
      item_type = of ? { "type" => of.to_s } : items
      item_type = self.class.define(&block).to_h if block
      prop = { "type" => "array" }
      prop["items"] = item_type if item_type
      add_property_entry(name, prop, optional: optional, default: default, description: description)
    end

    def object(name, properties: {}, optional: false, default: nil, description: nil, &block)
      props = block ? self.class.define(&block).properties : properties
      prop = { "type" => "object", "properties" => props }
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

    # rubocop:disable Metrics/ParameterLists
    def add_property(name, type, enum: nil, optional: false, default: nil, description: nil, minimum: nil, maximum: nil)
      # rubocop:enable Metrics/ParameterLists
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

  # Class-level schema definition for typed structured outputs.
  # Subclasses declare attributes with schema DSL and instantiate typed objects.
  class Schema
    class << self
      def dsl
        @dsl ||= SchemaDSL.new
      end

      def string(name, ...)
        dsl.string(name, ...)
        attr_reader name.to_sym
      end

      def number(name, ...)
        dsl.number(name, ...)
        attr_reader name.to_sym
      end

      def integer(name, ...)
        dsl.integer(name, ...)
        attr_reader name.to_sym
      end

      def boolean(name, ...)
        dsl.boolean(name, ...)
        attr_reader name.to_sym
      end

      def array(name, ...)
        dsl.array(name, ...)
        attr_reader name.to_sym
      end

      def object(name, ...)
        dsl.object(name, ...)
        attr_reader name.to_sym
      end

      def to_h
        dsl.to_h
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@dsl, SchemaDSL.new)
      end
    end

    attr_reader :attributes

    def initialize(attrs = {})
      @attributes = (attrs || {}).transform_keys(&:to_s)
      @attributes.each do |key, val|
        instance_variable_set("@#{key}", val) if respond_to?(key.to_sym)
      end
    end

    def [](key)
      @attributes[key.to_s]
    end

    def to_h
      @attributes
    end
  end
end

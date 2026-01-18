# frozen_string_literal: true

require_relative "../../dto"

module Ollama
  # Tool and Function classes are defined in tool.rb and tool/function.rb
  # This file adds Parameters class to Function
  class Tool
    # Function metadata and schema for tool calls.
    class Function
      # Parameters specification for a tool function
      #
      # Defines the structure of parameters that a function tool accepts.
      # This matches JSON Schema format used by Ollama's tool calling API.
      #
      # Example:
      #   parameters = Ollama::Tool::Function::Parameters.new(
      #     type: 'object',
      #     properties: {
      #       location: Ollama::Tool::Function::Parameters::Property.new(
      #         type: 'string',
      #         description: 'The location to get weather for'
      #       )
      #     },
      #     required: %w[location]
      #   )
      #
      #   # Deserialize from hash
      #   parameters = Ollama::Tool::Function::Parameters.from_hash({ type: 'object', ... })
      class Parameters
        include DTO

        attr_reader :type, :properties, :required

        def initialize(type:, properties: {}, required: [])
          @type = type.to_s
          @properties = normalize_properties(properties)
          @required = Array(required).map(&:to_s)
        end

        # Create instance from hash
        #
        # @param hash [Hash] Hash with type, properties, and optional required keys
        # @return [Parameters] New Parameters instance
        def self.from_hash(hash)
          normalized = hash.transform_keys(&:to_sym)
          props_hash = normalized[:properties] || normalized["properties"] || {}

          properties = props_hash.transform_values do |value|
            case value
            when Hash
              Property.from_hash(value)
            when Property
              value
            else
              raise Error, "Invalid property type: #{value.class}. Use Property or Hash"
            end
          end

          new(
            type: normalized[:type] || normalized["type"],
            properties: properties,
            required: normalized[:required] || normalized["required"] || []
          )
        end

        def to_h
          hash = { "type" => @type }
          hash["properties"] = @properties.transform_values(&:to_h) unless @properties.empty?
          hash["required"] = @required unless @required.empty?
          hash
        end

        # Override as_json to use explicit attributes instead of tracked ones
        def as_json(*_ignored)
          to_h
        end

        private

        def normalize_properties(props)
          return {} if props.nil? || props.empty?

          props.transform_values do |value|
            case value
            when Property
              value
            when Hash
              Property.from_hash(value)
            else
              raise Error, "Invalid property type: #{value.class}. Use Property or Hash"
            end
          end
        end
      end

      # Load Property class after Parameters is fully defined
      require_relative "parameters/property"
    end
  end
end

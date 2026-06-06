# frozen_string_literal: true

require_relative "../../../dto"

module Ollama
  # Tool, Function, and Parameters classes are defined in previous files
  # This file adds Property class to Parameters
  class Tool
    class Function
      class Parameters
        # A single property within the parameters specification
        #
        # Defines an individual parameter with its type, description, and
        # optional enumeration of valid values.
        #
        # Example:
        #   property = Ollama::Tool::Function::Parameters::Property.new(
        #     type: 'string',
        #     description: 'The location to get weather for'
        #   )
        #
        # Example with enum:
        #   property = Ollama::Tool::Function::Parameters::Property.new(
        #     type: 'string',
        #     description: 'Temperature unit',
        #     enum: %w[celsius fahrenheit]
        #   )
        #
        #   # Deserialize from hash
        #   property = Ollama::Tool::Function::Parameters::Property.from_hash({ type: 'string', ... })
        class Property
          include DTO

          attr_reader :type, :description, :enum

          def initialize(type:, description:, enum: nil)
            @type = type.to_s
            @description = description.to_s
            @enum = enum ? Array(enum).map(&:to_s) : nil
          end

          # Create instance from hash
          #
          # @param hash [Hash] Hash with type, description, and optional enum keys
          # @return [Property] New Property instance
          def self.from_hash(hash)
            normalized = hash.transform_keys(&:to_sym)
            new(
              type: normalized[:type] || normalized["type"],
              description: normalized[:description] || normalized["description"],
              enum: normalized[:enum] || normalized["enum"]
            )
          end

          def to_h
            hash = {
              "type" => @type,
              "description" => @description
            }
            hash["enum"] = @enum if @enum && !@enum.empty?
            hash
          end

          # Override as_json to use explicit attributes instead of tracked ones
          def as_json(*_ignored)
            to_h
          end
        end
      end
    end
  end
end

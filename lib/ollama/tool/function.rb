# frozen_string_literal: true

require_relative "../dto"

module Ollama
  # Tool class is defined in tool.rb
  # This file adds Function class to Tool
  class Tool
    # Represents a function definition for tool usage in Ollama API
    #
    # Provides structured, type-safe function definitions for agent tools.
    # Use this when you need explicit control over tool schemas beyond
    # auto-inference from Ruby callable signatures.
    #
    # Example:
    #   function = Ollama::Tool::Function.new(
    #     name: 'get_current_weather',
    #     description: 'Get the current weather for a location',
    #     parameters: parameters_spec
    #   )
    #
    #   # Deserialize from hash
    #   function = Ollama::Tool::Function.from_hash({ name: '...', description: '...' })
    class Function
      include DTO

      attr_reader :name, :description, :parameters

      def initialize(name:, description:, parameters: nil)
        @name = name.to_s
        @description = description.to_s
        @parameters = parameters || Function::Parameters.new(
          type: "object",
          properties: {},
          required: []
        )
      end

      # Create instance from hash
      #
      # @param hash [Hash] Hash with name, description, and optional parameters
      # @return [Function] New Function instance
      def self.from_hash(hash)
        normalized = hash.transform_keys(&:to_sym)
        params_hash = normalized[:parameters] || normalized["parameters"]

        parameters = if params_hash.is_a?(Hash)
                       Function::Parameters.from_hash(params_hash)
                     elsif params_hash
                       params_hash
                     else
                       nil
                     end

        new(
          name: normalized[:name] || normalized["name"],
          description: normalized[:description] || normalized["description"],
          parameters: parameters
        )
      end

      def to_h
        hash = {
          name: @name,
          description: @description
        }
        hash[:parameters] = @parameters.to_h if @parameters
        hash
      end

      # Override as_json to use explicit attributes instead of tracked ones
      def as_json(*_ignored)
        to_h
      end
    end

    # Load Parameters class after Function is defined
    require_relative "function/parameters"
  end
end

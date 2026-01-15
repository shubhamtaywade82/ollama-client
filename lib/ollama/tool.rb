# frozen_string_literal: true

require_relative "dto"
require_relative "tool/function"

module Ollama
  # Tool definition for function calling in agents
  #
  # Provides a structured, type-safe way to define tools for agent executors.
  # This is an optional alternative to passing raw callables - use when you
  # need explicit control over tool schemas.
  #
  # Example:
  #   tool = Ollama::Tool.new(
  #     type: 'function',
  #     function: Ollama::Tool::Function.new(
  #       name: 'get_weather',
  #       description: 'Get current weather',
  #       parameters: parameters_spec
  #     )
  #   )
  #
  #   # Deserialize from hash
  #   tool = Ollama::Tool.from_hash({ type: 'function', function: {...} })
  class Tool
    include DTO

    attr_reader :type, :function

    def initialize(type:, function:)
      @type = type.to_s
      @function = function
    end

    # Create instance from hash
    #
    # @param hash [Hash] Hash with type and function keys
    # @return [Tool] New Tool instance
    def self.from_hash(hash)
      normalized = hash.transform_keys(&:to_sym)
      function_hash = normalized[:function] || normalized["function"]
      function = function_hash.is_a?(Hash) ? Function.from_hash(function_hash) : function_hash

      new(type: normalized[:type] || normalized["type"], function: function)
    end

    def to_h
      {
        type: @type,
        function: @function.to_h
      }
    end

    # Override as_json to use explicit attributes instead of tracked ones
    # (since we're using to_h for our specific structure)
    def as_json(*_ignored)
      to_h
    end
  end
end

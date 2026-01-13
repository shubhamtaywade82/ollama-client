# frozen_string_literal: true

module Ollama
  # Options class for model parameters with basic type checking
  #
  # Provides type-safe access to Ollama model options.
  # Useful for agents that need to adjust model behavior dynamically.
  #
  # Example:
  #   options = Ollama::Options.new(temperature: 0.7, top_p: 0.95)
  #   client.generate(prompt: "...", schema: {...}, options: options.to_h)
  class Options
    attr_accessor :temperature, :top_p, :top_k, :num_ctx, :repeat_penalty, :seed

    def initialize(temperature: nil, top_p: nil, top_k: nil, num_ctx: nil, repeat_penalty: nil, seed: nil)
      self.temperature = temperature if temperature
      self.top_p = top_p if top_p
      self.top_k = top_k if top_k
      self.num_ctx = num_ctx if num_ctx
      self.repeat_penalty = repeat_penalty if repeat_penalty
      self.seed = seed if seed
    end

    def temperature=(value)
      validate_numeric_range(value, 0.0, 2.0, "temperature")
      @temperature = value
    end

    def top_p=(value)
      validate_numeric_range(value, 0.0, 1.0, "top_p")
      @top_p = value
    end

    def top_k=(value)
      validate_integer_min(value, 1, "top_k")
      @top_k = value
    end

    def num_ctx=(value)
      validate_integer_min(value, 1, "num_ctx")
      @num_ctx = value
    end

    def repeat_penalty=(value)
      validate_numeric_range(value, 0.0, 2.0, "repeat_penalty")
      @repeat_penalty = value
    end

    def seed=(value)
      validate_integer(value, "seed")
      @seed = value
    end

    # Convert to hash for API calls
    def to_h
      hash = {}
      hash[:temperature] = @temperature if @temperature
      hash[:top_p] = @top_p if @top_p
      hash[:top_k] = @top_k if @top_k
      hash[:num_ctx] = @num_ctx if @num_ctx
      hash[:repeat_penalty] = @repeat_penalty if @repeat_penalty
      hash[:seed] = @seed if @seed
      hash
    end

    private

    def validate_numeric_range(value, min, max, name)
      return if value.nil?

      unless value.is_a?(Numeric)
        raise ArgumentError, "#{name} must be numeric, got #{value.class}"
      end

      unless value >= min && value <= max
        raise ArgumentError, "#{name} must be between #{min} and #{max}, got #{value}"
      end
    end

    def validate_integer_min(value, min, name)
      return if value.nil?

      unless value.is_a?(Integer)
        raise ArgumentError, "#{name} must be an integer, got #{value.class}"
      end

      unless value >= min
        raise ArgumentError, "#{name} must be >= #{min}, got #{value}"
      end
    end

    def validate_integer(value, name)
      return if value.nil?

      unless value.is_a?(Integer)
        raise ArgumentError, "#{name} must be an integer, got #{value.class}"
      end
    end
  end
end

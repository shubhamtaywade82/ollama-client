# frozen_string_literal: true

module Ollama
  # Options class for model parameters with basic type checking
  #
  # Provides type-safe access to Ollama model runtime options.
  # These are passed under the `options:` key in API requests.
  #
  # Example:
  #   options = Ollama::Options.new(temperature: 0.7, top_p: 0.95, num_predict: 256)
  #   client.chat(messages: [...], options: options.to_h)
  #   client.generate(prompt: "...", options: options.to_h)
  #
  class Options
    VALID_KEYS = %i[
      temperature top_p top_k num_ctx repeat_penalty seed
      num_predict stop tfs_z mirostat mirostat_tau mirostat_eta
      num_gpu num_thread num_keep typical_p
      presence_penalty frequency_penalty
    ].freeze

    attr_reader :temperature, :top_p, :top_k, :num_ctx, :repeat_penalty, :seed,
                :num_predict, :stop, :tfs_z, :mirostat, :mirostat_tau, :mirostat_eta,
                :num_gpu, :num_thread, :num_keep, :typical_p,
                :presence_penalty, :frequency_penalty

    def initialize(**options)
      unknown_keys = options.keys - VALID_KEYS
      raise ArgumentError, "Unknown options: #{unknown_keys.join(", ")}" if unknown_keys.any?

      VALID_KEYS.each do |key|
        assign_option(key, options[key])
      end
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

    def num_predict=(value)
      validate_integer(value, "num_predict")
      @num_predict = value
    end

    def stop=(value)
      raise ArgumentError, "stop must be an Array of Strings" unless value.nil? || value.is_a?(Array)

      @stop = value
    end

    def tfs_z=(value)
      validate_numeric_min(value, 0.0, "tfs_z")
      @tfs_z = value
    end

    def mirostat=(value)
      raise ArgumentError, "mirostat must be 0, 1, or 2" unless value.nil? || [0, 1, 2].include?(value)

      @mirostat = value
    end

    def mirostat_tau=(value)
      validate_numeric_min(value, 0.0, "mirostat_tau")
      @mirostat_tau = value
    end

    def mirostat_eta=(value)
      validate_numeric_min(value, 0.0, "mirostat_eta")
      @mirostat_eta = value
    end

    def num_gpu=(value)
      validate_integer(value, "num_gpu")
      @num_gpu = value
    end

    def num_thread=(value)
      validate_integer_min(value, 1, "num_thread")
      @num_thread = value
    end

    def num_keep=(value)
      validate_integer(value, "num_keep")
      @num_keep = value
    end

    def typical_p=(value)
      validate_numeric_range(value, 0.0, 1.0, "typical_p")
      @typical_p = value
    end

    def presence_penalty=(value)
      validate_numeric_range(value, -2.0, 2.0, "presence_penalty")
      @presence_penalty = value
    end

    def frequency_penalty=(value)
      validate_numeric_range(value, -2.0, 2.0, "frequency_penalty")
      @frequency_penalty = value
    end

    # Convert to hash for API calls
    def to_h
      hash = {}
      VALID_KEYS.each do |key|
        val = instance_variable_get(:"@#{key}")
        hash[key] = val unless val.nil?
      end
      hash
    end

    private

    def assign_option(name, value)
      return if value.nil?

      public_send(:"#{name}=", value)
    end

    def validate_numeric_range(value, min, max, name)
      return if value.nil?

      raise ArgumentError, "#{name} must be numeric, got #{value.class}" unless value.is_a?(Numeric)

      return if value.between?(min, max)

      raise ArgumentError, "#{name} must be between #{min} and #{max}, got #{value}"
    end

    def validate_numeric_min(value, min, name)
      return if value.nil?

      raise ArgumentError, "#{name} must be numeric, got #{value.class}" unless value.is_a?(Numeric)

      return if value >= min

      raise ArgumentError, "#{name} must be >= #{min}, got #{value}"
    end

    def validate_integer_min(value, min, name)
      return if value.nil?

      raise ArgumentError, "#{name} must be an integer, got #{value.class}" unless value.is_a?(Integer)

      return if value >= min

      raise ArgumentError, "#{name} must be >= #{min}, got #{value}"
    end

    def validate_integer(value, name)
      return if value.nil?

      return if value.is_a?(Integer)

      raise ArgumentError, "#{name} must be an integer, got #{value.class}"
    end
  end
end

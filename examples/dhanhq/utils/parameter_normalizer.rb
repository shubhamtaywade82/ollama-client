# frozen_string_literal: true

require "json"

module DhanHQ
  module Utils
    # Normalizes parameters from LLM responses (handles arrays, stringified JSON, etc.)
    class ParameterNormalizer
      STRING_FIELDS = %w[symbol exchange_segment].freeze

      def self.normalize(params)
        return {} unless params.is_a?(Hash)

        params.each_with_object({}) do |(key, value), normalized|
          normalized[key] = if STRING_FIELDS.include?(key.to_s)
                              normalize_string_field(value)
                            else
                              value
                            end
        end
      end

      def self.normalize_string_field(value)
        return value.to_s if value.nil?

        if value.is_a?(Array) && !value.empty?
          value.first.to_s
        elsif value.is_a?(String) && value.strip.start_with?("[") && value.strip.end_with?("]")
          parse_stringified_array(value)
        else
          value.to_s
        end
      end

      def self.parse_stringified_array(value)
        parsed = JSON.parse(value)
        parsed.is_a?(Array) && !parsed.empty? ? parsed.first.to_s : value.to_s
      rescue JSON::ParserError
        value.to_s
      end

      private_class_method :normalize_string_field, :parse_stringified_array
    end
  end
end

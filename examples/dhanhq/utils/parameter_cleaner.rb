# frozen_string_literal: true

module DhanHQ
  module Utils
    # Cleans parameters from LLM responses (removes comments, instructions, etc.)
    class ParameterCleaner
      MAX_KEY_LENGTH = 50

      def self.clean(params)
        return {} unless params.is_a?(Hash)

        params.reject do |key, _value|
          key_str = key.to_s
          invalid_key?(key_str)
        end
      end

      def self.invalid_key?(key_str)
        key_str.start_with?(">") ||
          key_str.start_with?("//") ||
          key_str.include?("adjust") ||
          key_str.length > MAX_KEY_LENGTH
      end

      private_class_method :invalid_key?
    end
  end
end

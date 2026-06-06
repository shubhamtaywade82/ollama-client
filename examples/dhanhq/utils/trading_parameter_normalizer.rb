# frozen_string_literal: true

module DhanHQ
  module Utils
    # Normalizes trading parameters from LLM responses
    # Handles common issues like comma-separated numbers, string numbers, etc.
    class TradingParameterNormalizer
      NUMERIC_FIELDS = %w[price target_price stop_loss_price quantity trailing_jump].freeze

      def self.normalize(params)
        return {} unless params.is_a?(Hash)

        params.each_with_object({}) do |(key, value), normalized|
          key_str = key.to_s
          normalized[key] = if NUMERIC_FIELDS.include?(key_str)
                              normalize_numeric(value)
                            elsif key_str == "security_id"
                              normalize_security_id(value)
                            else
                              value
                            end
        end
      end

      def self.normalize_numeric(value)
        return nil if value.nil?

        # If already a number, return as-is (but validate it's reasonable)
        return value if value.is_a?(Numeric)

        # If string, clean and convert
        return nil unless value.is_a?(String)

        # Remove commas, spaces, currency symbols, and convert
        cleaned = value.to_s.gsub(/[,\s$₹]/, "")
        return nil if cleaned.empty?

        # Try to convert to float (for prices) or integer (for quantity)
        if cleaned.include?(".")
          cleaned.to_f
        else
          cleaned.to_i
        end
      rescue StandardError
        nil
      end

      # Validates if a price value seems reasonable (not obviously wrong)
      def self.valid_price?(price, context_hint = nil)
        return false if price.nil?

        # If price is suspiciously low (< 10), it might be wrong
        # But we can't be too strict since some stocks might legitimately be < 10
        # Check if context hint suggests a higher price
        if price.is_a?(Numeric) && price.positive? && price < 10 &&
           context_hint.is_a?(Numeric) && context_hint > price * 100
          return false # Likely wrong
        end

        true
      end

      def self.normalize_security_id(value)
        return nil if value.nil?

        value.to_s
      end

      private_class_method :normalize_numeric, :normalize_security_id, :valid_price?
    end
  end
end

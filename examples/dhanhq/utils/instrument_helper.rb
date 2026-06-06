# frozen_string_literal: true

module DhanHQ
  module Utils
    # Helper utilities for working with DhanHQ instruments
    class InstrumentHelper
      def self.safe_attr(instrument, attr_name)
        return nil unless instrument

        instrument.respond_to?(attr_name) ? instrument.send(attr_name) : nil
      rescue StandardError
        nil
      end

      def self.extract_value(data, keys)
        return nil unless data

        keys.each do |key|
          if data.is_a?(Hash)
            return data[key] if data.key?(key)
          elsif data.respond_to?(key)
            return data.send(key)
          end
        end

        return data if data.is_a?(Numeric) || data.is_a?(String)

        nil
      end
    end
  end
end

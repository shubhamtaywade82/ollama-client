# frozen_string_literal: true

require_relative "../utils/instrument_helper"
require_relative "../utils/rate_limiter"

module DhanHQ
  module Services
    # Base service class with common functionality
    class BaseService
      protected

      def find_instrument(exchange_segment, symbol)
        DhanHQ::Models::Instrument.find(exchange_segment, symbol)
      end

      def safe_attr(instrument, attr_name)
        DhanHQ::Utils::InstrumentHelper.safe_attr(instrument, attr_name)
      end

      def extract_value(data, keys)
        DhanHQ::Utils::InstrumentHelper.extract_value(data, keys)
      end

      def rate_limit_marketfeed
        DhanHQ::Utils::RateLimiter.marketfeed
      end

      def resolve_security_id(security_id, symbol, exchange_segment)
        return security_id.to_s if security_id

        instrument = find_instrument(exchange_segment, symbol.to_s)
        return nil unless instrument

        safe_attr(instrument, :security_id)&.to_s
      end

      def error_response(action, error, params = {})
        { action: action, error: error, params: params }
      end

      def success_response(action, result, params = {})
        { action: action, params: params, result: result }
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base_service"
require_relative "../../dhanhq_tools"

module DhanHQ
  module Services
    # Service for executing data retrieval actions
    class DataService < BaseService
      def execute(action:, params:)
        case action
        when "get_market_quote"
          execute_market_quote(params)
        when "get_live_ltp"
          execute_live_ltp(params)
        when "get_market_depth"
          execute_market_depth(params)
        when "get_historical_data"
          execute_historical_data(params)
        when "get_option_chain"
          execute_option_chain(params)
        when "get_expired_options_data"
          execute_expired_options_data(params)
        when "no_action"
          { action: "no_action", message: "No action taken" }
        else
          { action: "unknown", error: "Unknown action: #{action}" }
        end
      end

      private

      def execute_market_quote(params)
        validate_symbol_or_id(params, "get_market_quote") ||
          DhanHQDataTools.get_market_quote(
            symbol: params["symbol"],
            security_id: params["security_id"],
            exchange_segment: params["exchange_segment"] || "NSE_EQ"
          )
      end

      def execute_live_ltp(params)
        validate_symbol_or_id(params, "get_live_ltp") ||
          DhanHQDataTools.get_live_ltp(
            symbol: params["symbol"],
            security_id: params["security_id"],
            exchange_segment: params["exchange_segment"] || "NSE_EQ"
          )
      end

      def execute_market_depth(params)
        validate_symbol_or_id(params, "get_market_depth") ||
          DhanHQDataTools.get_market_depth(
            symbol: params["symbol"],
            security_id: params["security_id"],
            exchange_segment: params["exchange_segment"] || "NSE_EQ"
          )
      end

      def execute_historical_data(params)
        validate_symbol_or_id(params, "get_historical_data") ||
          DhanHQDataTools.get_historical_data(
            symbol: params["symbol"],
            security_id: params["security_id"],
            exchange_segment: params["exchange_segment"] || "NSE_EQ",
            from_date: params["from_date"],
            to_date: params["to_date"],
            interval: params["interval"],
            expiry_code: params["expiry_code"]
          )
      end

      def execute_option_chain(params)
        validate_symbol_or_id(params, "get_option_chain") ||
          DhanHQDataTools.get_option_chain(
            symbol: params["symbol"],
            security_id: params["security_id"],
            exchange_segment: params["exchange_segment"] || "NSE_EQ",
            expiry: params["expiry"]
          )
      end

      def execute_expired_options_data(params)
        if missing_expired_options_params?(params)
          return error_response("get_expired_options_data",
                                "Either symbol or security_id, and expiry_date are required",
                                params)
        end

        DhanHQDataTools.get_expired_options_data(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_FNO",
          expiry_date: params["expiry_date"],
          expiry_code: params["expiry_code"],
          interval: params["interval"] || "1",
          instrument: params["instrument"],
          expiry_flag: params["expiry_flag"] || "MONTH",
          strike: params["strike"] || "ATM",
          drv_option_type: params["drv_option_type"] || "CALL",
          required_data: params["required_data"]
        )
      end

      def validate_symbol_or_id(params, action)
        return nil unless params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)

        error_response(action, "Either symbol or security_id is required", params)
      end

      def missing_expired_options_params?(params)
        symbol_or_id_missing = params["symbol"].nil? &&
                               (params["security_id"].nil? || params["security_id"].to_s.empty?)
        symbol_or_id_missing || params["expiry_date"].nil?
      end
    end
  end
end

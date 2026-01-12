# frozen_string_literal: true

require_relative "base_service"
require_relative "../../dhanhq_tools"

# Keep backward compatibility
DhanHQTradingTools = DhanHQTradingTools unless defined?(DhanHQTradingTools)

module DhanHQ
  module Services
    # Service for executing trading order actions
    class TradingService < BaseService
      def execute(action:, params:)
        case action
        when "place_order"
          execute_place_order(params)
        when "place_super_order"
          execute_place_super_order(params)
        when "cancel_order"
          execute_cancel_order(params)
        when "no_action"
          { action: "no_action", message: "No action taken" }
        else
          { action: "unknown", error: "Unknown action: #{action}" }
        end
      end

      private

      def execute_place_order(params)
        DhanHQTradingTools.build_order_params(
          transaction_type: params["transaction_type"] || "BUY",
          exchange_segment: params["exchange_segment"] || "NSE_EQ",
          product_type: params["product_type"] || "MARGIN",
          order_type: params["order_type"] || "LIMIT",
          security_id: params["security_id"],
          quantity: params["quantity"] || 1,
          price: params["price"]
        )
      end

      def execute_place_super_order(params)
        DhanHQTradingTools.build_super_order_params(
          transaction_type: params["transaction_type"] || "BUY",
          exchange_segment: params["exchange_segment"] || "NSE_EQ",
          product_type: params["product_type"] || "MARGIN",
          order_type: params["order_type"] || "LIMIT",
          security_id: params["security_id"],
          quantity: params["quantity"] || 1,
          price: params["price"],
          target_price: params["target_price"],
          stop_loss_price: params["stop_loss_price"],
          trailing_jump: params["trailing_jump"] || 10
        )
      end

      def execute_cancel_order(params)
        DhanHQTradingTools.build_cancel_params(order_id: params["order_id"])
      end
    end
  end
end

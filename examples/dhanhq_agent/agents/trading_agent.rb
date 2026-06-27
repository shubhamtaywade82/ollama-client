# frozen_string_literal: true

module DhanHQAgent
  module Agents
    class TradingAgent
      MIN_CONFIDENCE = 0.6

      def initialize(ollama_client:)
        @ollama_client = ollama_client
      end

      def analyze_and_decide(market_context:)
        decision = generate_decision(market_context: market_context)
        clean_parameters!(decision)

        return { action: "no_action", reason: "invalid_decision" } unless valid_decision?(decision)
        return low_confidence_decision(decision["confidence"]) if decision["confidence"] < MIN_CONFIDENCE

        decision
      rescue Ollama::Error => e
        puts "❌ Ollama error: #{e.message}"
        { action: "no_action", reason: "error", error: e.message }
      rescue StandardError => e
        puts "❌ Unexpected error: #{e.message}"
        { action: "no_action", reason: "error", error: e.message }
      end

      def execute_decision(decision)
        action = decision["action"]
        params = decision["parameters"] || {}

        case action
        when "place_order" then build_order(params)
        when "place_super_order" then build_super_order(params)
        when "cancel_order" then build_cancel(params)
        when "no_action" then no_action
        else unknown_action(action)
        end
      end

      private

      attr_reader :ollama_client

      def generate_decision(market_context:)
        ollama_client.generate(
          prompt: analysis_prompt(market_context: market_context),
          schema: decision_schema
        )
      end

      def clean_parameters!(decision)
        return unless decision.is_a?(Hash) && decision["parameters"].is_a?(Hash)

        decision["parameters"] = decision["parameters"].reject do |key, _value|
          key_str = key.to_s
          key_str.start_with?(">") || key_str.start_with?("//") || key_str.include?("adjust") || key_str.length > 50
        end
      end

      def valid_decision?(decision)
        decision.is_a?(Hash) && decision["confidence"]
      end

      def low_confidence_decision(confidence)
        puts "⚠️  Low confidence (#{(confidence * 100).round}%) - skipping action"
        { action: "no_action", reason: "low_confidence" }
      end

      def build_order(params)
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

      def build_super_order(params)
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

      def build_cancel(params)
        DhanHQTradingTools.build_cancel_params(order_id: params["order_id"])
      end

      def no_action
        { action: "no_action", message: "No action taken" }
      end

      def unknown_action(action)
        { action: "unknown", error: "Unknown action: #{action}" }
      end

      def decision_schema
        @decision_schema ||= {
          "type" => "object",
          "required" => ["action", "reasoning", "confidence"],
          "properties" => {
            "action" => {
              "type" => "string",
              "enum" => ["place_order", "place_super_order", "cancel_order", "no_action"]
            },
            "reasoning" => {
              "type" => "string",
              "description" => "Why this action was chosen"
            },
            "confidence" => {
              "type" => "number",
              "minimum" => 0,
              "maximum" => 1,
              "description" => "Confidence in this decision"
            },
            "parameters" => {
              "type" => "object",
              "additionalProperties" => true,
              "description" => "Parameters for the action (security_id, quantity, price, etc.)"
            }
          }
        }
      end

      def analysis_prompt(market_context:)
        <<~PROMPT
          Analyze the following market situation and decide the best trading action:

          Market Context:
          #{market_context}

          Available Actions (TRADING ONLY):
          - place_order: Build order parameters (requires: security_id as string, quantity, price, transaction_type, exchange_segment)
          - place_super_order: Build super order parameters with SL/TP (requires: security_id as string, quantity, price, target_price, stop_loss_price, exchange_segment)
          - cancel_order: Build cancel parameters (requires: order_id)
          - no_action: Take no action if market conditions are unclear or risky

          Important: security_id must be a STRING (e.g., "13" not 13). Valid exchange_segment values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

          CRITICAL: The parameters object must contain ONLY valid parameter values (strings, numbers, etc.).
          DO NOT include comments, instructions, or explanations in the parameters object.
          Parameters should be clean JSON values only.

          Decision Criteria:
          - Only take actions with confidence > 0.6
          - Consider risk management (use super orders for risky trades)
          - Ensure all required parameters are provided
          - Be conservative - prefer no_action if uncertain

          Respond with a JSON object containing:
          - action: one of the available trading actions
          - reasoning: why this action was chosen (put explanations here, NOT in parameters)
          - confidence: your confidence level (0-1)
          - parameters: object with ONLY required parameter values (no comments, no explanations)
        PROMPT
      end
    end
  end
end


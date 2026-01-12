# frozen_string_literal: true

require_relative "base_agent"
require_relative "../schemas/agent_schemas"
require_relative "../services/trading_service"
require_relative "../utils/trading_parameter_normalizer"

module DhanHQ
  module Agents
    # Agent for trading order decisions using LLM
    class TradingAgent < BaseAgent
      def initialize(ollama_client:)
        super(ollama_client: ollama_client, schema: DhanHQ::Schemas::AgentSchemas::TRADING_AGENT_SCHEMA)
        @trading_service = DhanHQ::Services::TradingService.new
      end

      def execute_decision(decision)
        action = decision["action"]
        raw_params = decision["parameters"] || {}
        params = DhanHQ::Utils::TradingParameterNormalizer.normalize(raw_params)

        # Warn if price seems suspiciously low
        if params["price"] && params["price"] < 10
          puts "⚠️  Warning: Price value (#{params['price']}) seems unusually low. Please verify."
        end

        @trading_service.execute(action: action, params: params)
      end

      protected

      def build_analysis_prompt(market_context:)
        <<~PROMPT
          Analyze the following market situation and decide the best trading action:

          Market Context:
          #{market_context}

          Available Actions (TRADING ONLY):
          - place_order: Build order parameters (requires: security_id as string, quantity, price, transaction_type, exchange_segment)
          - place_super_order: Build super order parameters with SL/TP (requires: security_id as string, quantity, price, target_price, stop_loss_price, exchange_segment)
          - cancel_order: Build cancel parameters (requires: order_id)
          - no_action: Take no action if market conditions are unclear or risky

          CRITICAL PARAMETER EXTRACTION RULES:
          1. security_id must be a STRING (e.g., "13" not 13)
          2. price, target_price, stop_loss_price must be NUMERIC values (numbers, not strings)
          3. When extracting prices from context:
             - "2,850" means 2850 (remove commas, convert to number)
             - "1,483.2" means 1483.2 (remove commas, keep decimal)
             - Use the EXACT numeric value from context, do NOT approximate
             - If context says "Entry price: 2,850", use 2850 (not 2, not 285, not any approximation)
          4. quantity must be a positive integer
          5. Valid exchange_segment values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

          CRITICAL: The parameters object must contain ONLY valid parameter values (strings, numbers, etc.).
          DO NOT include comments, instructions, explanations, or descriptions in the parameters object.
          Parameters should be clean JSON values only.

          Example of CORRECT parameter extraction:
          Context: "Entry price: 2,850, Quantity: 100, security_id='1333'"
          Correct parameters: {"security_id": "1333", "quantity": 100, "price": 2850}
          WRONG: {"price": 2, "description": "approximation"} ❌
          WRONG: {"price": "2850"} ❌ (should be number, not string)

          Decision Criteria:
          - Only take actions with confidence > 0.6
          - Consider risk management (use super orders for risky trades)
          - Ensure all required parameters are provided with EXACT values from context
          - Be conservative - prefer no_action if uncertain

          Respond with a JSON object containing:
          - action: one of the available trading actions
          - reasoning: why this action was chosen (put explanations here, NOT in parameters)
          - confidence: your confidence level (0-1)
          - parameters: object with ONLY required parameter values (no comments, no explanations, exact numeric values)
        PROMPT
      end
    end
  end
end

# frozen_string_literal: true

require_relative "base_agent"
require_relative "../schemas/agent_schemas"
require_relative "../services/data_service"

module DhanHQ
  module Agents
    # Agent for market data retrieval decisions using LLM
    class DataAgent < BaseAgent
      def initialize(ollama_client:)
        super(ollama_client: ollama_client, schema: DhanHQ::Schemas::AgentSchemas::DATA_AGENT_SCHEMA)
        @data_service = DhanHQ::Services::DataService.new
      end

      def execute_decision(decision)
        action = decision["action"]
        params = DhanHQ::Utils::ParameterNormalizer.normalize(decision["parameters"] || {})

        @data_service.execute(action: action, params: params)
      end

      protected

      def build_analysis_prompt(market_context:)
        <<~PROMPT
          Analyze the following market situation and decide the best data retrieval action:

          Market Context:
          #{market_context}

          Available Actions (DATA ONLY - NO TRADING):
          - get_market_quote: Get market quote using Instrument.quote convenience method (requires: symbol OR security_id as STRING, exchange_segment as STRING)
          - get_live_ltp: Get live last traded price using Instrument.ltp convenience method (requires: symbol OR security_id as STRING, exchange_segment as STRING)
          - get_market_depth: Get full market depth (bid/ask levels) using Instrument.quote convenience method (requires: symbol OR security_id as STRING, exchange_segment as STRING)
          - get_historical_data: Get historical data using Instrument.daily/intraday convenience methods (requires: symbol OR security_id as STRING, exchange_segment as STRING, from_date, to_date, optional: interval, expiry_code)
          - get_expired_options_data: Get expired options historical data (requires: symbol OR security_id as STRING, exchange_segment as STRING, expiry_date; optional: expiry_code, interval, instrument, expiry_flag, strike, drv_option_type, required_data)
          - get_option_chain: Get option chain using Instrument.expiry_list/option_chain convenience methods (requires: symbol OR security_id as STRING, exchange_segment as STRING, optional: expiry)
          - no_action: Take no action if unclear what data is needed

          CRITICAL: Each API call handles ONLY ONE symbol at a time. If you need data for multiple symbols, choose ONE symbol for this decision.
          - symbol must be a SINGLE STRING value (e.g., "NIFTY" or "RELIANCE"), NOT an array
          - exchange_segment must be a SINGLE STRING value (e.g., "NSE_EQ" or "IDX_I"), NOT an array
          - All APIs use Instrument.find() which expects SYMBOL (e.g., "NIFTY", "RELIANCE"), not security_id
          - Instrument convenience methods automatically use the instrument's security_id, exchange_segment, and instrument attributes
          - Use symbol when possible for better compatibility
          Examples:
            - For NIFTY: symbol="NIFTY", exchange_segment="IDX_I"
            - For RELIANCE: symbol="RELIANCE", exchange_segment="NSE_EQ"
          Valid exchange_segments: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

          Decision Criteria:
          - Only take actions with confidence > 0.6
          - Focus on data retrieval, not trading decisions
          - Provide all required parameters for the chosen action

          Respond with a JSON object containing:
          - action: one of the available actions
          - reasoning: why this action was chosen
          - confidence: your confidence level (0-1)
          - parameters: object with required parameters for the action
        PROMPT
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module DhanHQAgent
  module Agents
    class DataAgent
      MIN_CONFIDENCE = 0.6

      def initialize(ollama_client:)
        @ollama_client = ollama_client
      end

      def analyze_and_decide(market_context:)
        decision = generate_decision(market_context: market_context)
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
        params = normalize_parameters(decision["parameters"] || {})

        executor.call(action: action, params: params)
      end

      private

      attr_reader :ollama_client

      def executor
        @executor ||= DataToolsExecutor.new
      end

      def generate_decision(market_context:)
        ollama_client.generate(
          prompt: analysis_prompt(market_context: market_context),
          schema: decision_schema
        )
      end

      def valid_decision?(decision)
        decision.is_a?(Hash) && decision["confidence"]
      end

      def low_confidence_decision(confidence)
        puts "⚠️  Low confidence (#{(confidence * 100).round}%) - skipping action"
        { action: "no_action", reason: "low_confidence" }
      end

      def normalize_parameters(params)
        params.each_with_object({}) do |(key, value), normalized|
          normalized[key] = normalized_parameter_value(key: key, value: value)
        end
      end

      def normalized_parameter_value(key:, value:)
        return value unless %w[symbol exchange_segment].include?(key.to_s)

        first_array_element(value) || first_stringified_array_element(value) || value.to_s
      end

      def first_array_element(value)
        return nil unless value.is_a?(Array) && !value.empty?

        value.first.to_s
      end

      def first_stringified_array_element(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        return nil unless stripped.start_with?("[") && stripped.end_with?("]")

        parsed = JSON.parse(stripped)
        return nil unless parsed.is_a?(Array) && !parsed.empty?

        parsed.first.to_s
      rescue JSON::ParserError
        nil
      end

      def decision_schema
        @decision_schema ||= {
          "type" => "object",
          "required" => ["action", "reasoning", "confidence"],
          "properties" => {
            "action" => {
              "type" => "string",
              "enum" => [
                "get_market_quote",
                "get_live_ltp",
                "get_market_depth",
                "get_historical_data",
                "get_expired_options_data",
                "get_option_chain",
                "no_action"
              ]
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
              "description" => "Parameters for the action (symbol, exchange_segment, etc.)"
            }
          }
        }
      end

      def analysis_prompt(market_context:)
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

    class DataToolsExecutor
      def call(action:, params:)
        handler = handlers.fetch(action) { return unknown_action(action) }
        handler.call(params)
      end

      private

      def handlers
        @handlers ||= {
          "get_market_quote" => method(:get_market_quote),
          "get_live_ltp" => method(:get_live_ltp),
          "get_market_depth" => method(:get_market_depth),
          "get_historical_data" => method(:get_historical_data),
          "get_option_chain" => method(:get_option_chain),
          "get_expired_options_data" => method(:get_expired_options_data),
          "no_action" => method(:no_action)
        }
      end

      def no_action(_params)
        { action: "no_action", message: "No action taken" }
      end

      def get_market_quote(params)
        return symbol_or_id_required(action: "get_market_quote", params: params) if symbol_or_id_missing?(params)

        DhanHQDataTools.get_market_quote(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

      def get_live_ltp(params)
        return symbol_or_id_required(action: "get_live_ltp", params: params) if symbol_or_id_missing?(params)

        DhanHQDataTools.get_live_ltp(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

      def get_market_depth(params)
        return symbol_or_id_required(action: "get_market_depth", params: params) if symbol_or_id_missing?(params)

        DhanHQDataTools.get_market_depth(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ"
        )
      end

      def get_historical_data(params)
        return symbol_or_id_required(action: "get_historical_data", params: params) if symbol_or_id_missing?(params)

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

      def get_option_chain(params)
        return symbol_or_id_required(action: "get_option_chain", params: params) if symbol_or_id_missing?(params)

        DhanHQDataTools.get_option_chain(
          symbol: params["symbol"],
          security_id: params["security_id"],
          exchange_segment: params["exchange_segment"] || "NSE_EQ",
          expiry: params["expiry"]
        )
      end

      def get_expired_options_data(params)
        symbol_or_id_missing = symbol_or_id_missing?(params)
        return expiry_date_and_symbol_or_id_required(params) if symbol_or_id_missing || params["expiry_date"].nil?

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

      def symbol_or_id_missing?(params)
        params["symbol"].nil? && (params["security_id"].nil? || params["security_id"].to_s.empty?)
      end

      def symbol_or_id_required(action:, params:)
        { action: action, error: "Either symbol or security_id is required", params: params }
      end

      def expiry_date_and_symbol_or_id_required(params)
        {
          action: "get_expired_options_data",
          error: "Either symbol or security_id, and expiry_date are required",
          params: params
        }
      end

      def unknown_action(action)
        { action: "unknown", error: "Unknown action: #{action}" }
      end
    end
  end
end


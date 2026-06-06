# frozen_string_literal: true

module DhanHQ
  module Schemas
    # JSON schemas for agent decision-making
    class AgentSchemas
      DATA_AGENT_SCHEMA = {
        "type" => "object",
        "required" => ["action", "reasoning", "confidence"],
        "properties" => {
          "action" => {
            "type" => "string",
            "enum" => ["get_market_quote", "get_live_ltp", "get_market_depth", "get_historical_data",
                       "get_expired_options_data", "get_option_chain", "no_action"]
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
      }.freeze

      TRADING_AGENT_SCHEMA = {
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
      }.freeze
    end
  end
end

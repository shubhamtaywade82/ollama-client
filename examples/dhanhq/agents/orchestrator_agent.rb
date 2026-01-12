# frozen_string_literal: true

require_relative "base_agent"
require_relative "../schemas/agent_schemas"

module DhanHQ
  module Agents
    # Orchestrator agent that uses LLM to decide what to analyze
    class OrchestratorAgent < BaseAgent
      def initialize(ollama_client:)
        super(ollama_client: ollama_client, schema: build_orchestration_schema)
      end

      def decide_analysis_plan(market_context: "", user_query: "")
        prompt = build_orchestration_prompt(market_context: market_context, user_query: user_query)

        begin
          plan = @ollama_client.generate(
            prompt: prompt,
            schema: build_orchestration_schema
          )

          return { error: "Invalid plan" } unless plan.is_a?(Hash) && plan["analysis_plan"]

          plan
        rescue Ollama::Error => e
          { error: e.message }
        end
      end

      protected

      def build_analysis_prompt(market_context:)
        # Not used, but required by base class
        ""
      end

      private

      def build_orchestration_prompt(market_context:, user_query:)
        <<~PROMPT
          You are a trading analysis orchestrator. Based on the market context and user query, decide what technical analysis to perform.

          Market Context:
          #{market_context.empty? ? 'No specific market context provided' : market_context}

          User Query:
          #{user_query.empty? ? 'No specific query - analyze current market opportunities' : user_query}

          Your task is to create an analysis plan that includes:
          1. Which symbols to analyze:
             - Equity stocks: "RELIANCE", "TCS", "INFY", "HDFC" (use NSE_EQ or BSE_EQ)
             - Indices: "NIFTY", "SENSEX", "BANKNIFTY" (use IDX_I)
          2. Which exchange segments to use:
             - NSE_EQ or BSE_EQ for equity stocks
             - IDX_I for indices (NIFTY, SENSEX, BANKNIFTY)
          3. What type of analysis to perform:
             - "technical_analysis": Full technical analysis (trend, indicators, patterns) - can be used for both stocks and indices
             - "swing_scan": Scan for swing trading opportunities - ONLY for equity stocks, NEVER for indices
             - "options_scan": Scan for intraday options opportunities - ONLY for indices (NIFTY, SENSEX, BANKNIFTY)
             - "all": Run all applicable analysis types (swing_scan only for stocks, options_scan only for indices)
          4. Priority order (which symbols/analyses to run first)

          Consider:
          - If user mentions specific stocks, prioritize those
          - If user asks about "swing trading", use swing_scan ONLY for equity stocks (not indices)
          - If user asks about "options" or "intraday", use options_scan
          - If no specific query, scan for opportunities across multiple symbols
          - CRITICAL: Index symbols (NIFTY, SENSEX, BANKNIFTY) are INDICES, not stocks
            * Indices should ONLY be analyzed with options_scan (for options buying opportunities)
            * Indices should NEVER be analyzed with swing_scan (swing trading is for stocks only)
          - For options, use index symbols (NIFTY, SENSEX, BANKNIFTY) with IDX_I segment
          - For swing trading, use ONLY equity symbols (RELIANCE, TCS, INFY, HDFC) with NSE_EQ or BSE_EQ segment

          Respond with a JSON object containing your analysis plan.
        PROMPT
      end

      def build_orchestration_schema
        {
          "type" => "object",
          "required" => ["analysis_plan", "reasoning"],
          "properties" => {
            "analysis_plan" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "required" => ["symbol", "exchange_segment", "analysis_type"],
                "properties" => {
                  "symbol" => {
                    "type" => "string",
                    "description" => "Symbol to analyze (e.g., 'RELIANCE', 'NIFTY', 'TCS')"
                  },
                  "exchange_segment" => {
                    "type" => "string",
                    "enum" => ["NSE_EQ", "NSE_FNO", "NSE_CURRENCY", "BSE_EQ", "BSE_FNO",
                               "BSE_CURRENCY", "MCX_COMM", "IDX_I"],
                    "description" => "Exchange segment for the symbol"
                  },
                  "analysis_type" => {
                    "type" => "string",
                    "enum" => ["technical_analysis", "swing_scan", "options_scan", "all"],
                    "description" => "Type of analysis to perform"
                  },
                  "priority" => {
                    "type" => "number",
                    "description" => "Priority (1 = highest, lower numbers = higher priority)"
                  }
                }
              }
            },
            "reasoning" => {
              "type" => "string",
              "description" => "Why you chose this analysis plan"
            }
          }
        }
      end
    end
  end
end

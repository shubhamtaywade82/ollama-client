# frozen_string_literal: true

require_relative "base_agent"
require_relative "../schemas/agent_schemas"
require_relative "../analysis/trend_analyzer"
require_relative "../services/data_service"

module DhanHQ
  module Agents
    # Agent for technical analysis and trading recommendations
    class TechnicalAnalysisAgent < BaseAgent
      def initialize(ollama_client:)
        super(ollama_client: ollama_client, schema: build_analysis_schema)
        @data_service = Services::DataService.new
      end

      def analyze_symbol(symbol:, exchange_segment:)
        # Fetch historical data
        result = @data_service.execute(
          action: "get_historical_data",
          params: {
            "symbol" => symbol,
            "exchange_segment" => exchange_segment,
            "from_date" => (Date.today - 60).strftime("%Y-%m-%d"),
            "to_date" => Date.today.strftime("%Y-%m-%d")
          }
        )

        return { error: "Failed to fetch data: #{result[:error] || 'Unknown error'}" } if result[:error]
        return { error: "No result data returned" } unless result[:result]

        # Convert to OHLC format
        ohlc_data = convert_to_ohlc(result)

        if ohlc_data.nil? || ohlc_data.empty?
          return { error: "Failed to convert data to OHLC format (empty or invalid data)" }
        end

        # Perform technical analysis
        analysis = Analysis::TrendAnalyzer.analyze(ohlc_data)

        return { error: "Analysis returned empty result" } if analysis.nil? || analysis.empty?

        # Get LLM interpretation
        interpretation = interpret_analysis(symbol, analysis)

        {
          symbol: symbol,
          exchange_segment: exchange_segment,
          analysis: analysis,
          interpretation: interpretation
        }
      end

      def generate_recommendation(analysis_result, trading_style: :swing)
        market_context = build_market_context(analysis_result)

        prompt = build_recommendation_prompt(market_context, trading_style)

        begin
          @ollama_client.generate(
            prompt: prompt,
            schema: build_recommendation_schema(trading_style)
          )
        rescue Ollama::Error => e
          { error: e.message }
        end
      end

      protected

      def build_analysis_prompt(market_context:)
        # Not used in this agent, but required by base class
        ""
      end

      private

      def convert_to_ohlc(historical_data)
        return [] unless historical_data.is_a?(Hash)

        # Navigate to the actual data: result -> result -> data
        outer_result = historical_data[:result] || historical_data["result"]
        return [] unless outer_result.is_a?(Hash)

        data = outer_result[:data] || outer_result["data"]
        return [] unless data

        # Handle DhanHQ format: {open: [...], high: [...], low: [...], close: [...], volume: [...]}
        if data.is_a?(Hash)
          opens = data[:open] || data["open"] || []
          highs = data[:high] || data["high"] || []
          lows = data[:low] || data["low"] || []
          closes = data[:close] || data["close"] || []
          volumes = data[:volume] || data["volume"] || []

          return [] if closes.nil? || closes.empty?

          # Convert parallel arrays to array of hashes
          max_length = [opens.length, highs.length, lows.length, closes.length].max
          return [] if max_length.zero?

          ohlc_data = []

          (0...max_length).each do |i|
            ohlc_data << {
              open: opens[i] || closes[i] || 0,
              high: highs[i] || closes[i] || 0,
              low: lows[i] || closes[i] || 0,
              close: closes[i] || 0,
              volume: volumes[i] || 0
            }
          end

          return ohlc_data
        end

        # Handle array format: [{open, high, low, close, volume}, ...]
        if data.is_a?(Array)
          return data.map do |bar|
            next nil unless bar.is_a?(Hash)

            {
              open: bar["open"] || bar[:open],
              high: bar["high"] || bar[:high],
              low: bar["low"] || bar[:low],
              close: bar["close"] || bar[:close],
              volume: bar["volume"] || bar[:volume]
            }
          end.compact
        end

        []
      end

      def interpret_analysis(symbol, analysis)
        context = <<~CONTEXT
          Technical Analysis for #{symbol}:

          Trend: #{analysis[:trend][:trend]} (Strength: #{analysis[:trend][:strength]}%)
          RSI: #{analysis[:indicators][:rsi]&.round(2) || 'N/A'}
          MACD: #{analysis[:indicators][:macd]&.round(2) || 'N/A'}
          Current Price: #{analysis[:current_price]}

          Patterns: #{analysis[:patterns][:candlestick].length} candlestick patterns detected
          Structure Break: #{analysis[:structure_break][:broken] ? 'Yes' : 'No'}
        CONTEXT

        begin
          @ollama_client.generate(
            prompt: "Interpret this technical analysis: #{context}",
            schema: {
              "type" => "object",
              "properties" => {
                "summary" => { "type" => "string" },
                "sentiment" => { "type" => "string", "enum" => ["bullish", "bearish", "neutral"] },
                "key_levels" => { "type" => "array", "items" => { "type" => "number" } }
              }
            }
          )
        rescue Ollama::Error
          { summary: "Analysis completed", sentiment: "neutral" }
        end
      end

      def build_market_context(analysis_result)
        analysis = analysis_result[:analysis]
        <<~CONTEXT
          Symbol: #{analysis_result[:symbol]}
          Current Price: #{analysis[:current_price]}
          Trend: #{analysis[:trend][:trend]} (#{analysis[:trend][:strength]}% strength)
          RSI: #{analysis[:indicators][:rsi]&.round(2) || 'N/A'}
          MACD: #{analysis[:indicators][:macd]&.round(2) || 'N/A'} (Signal: #{analysis[:indicators][:macd_signal]&.round(2) || 'N/A'})
          Structure Break: #{analysis[:structure_break][:broken] ? 'Yes' : 'No'}
          Patterns: #{analysis[:patterns][:candlestick].length} recent patterns
        CONTEXT
      end

      def build_recommendation_prompt(market_context, trading_style)
        style_instructions = case trading_style
                             when :intraday
                               "Focus on intraday moves, entry/exit within same day, use tight stops"
                             when :swing
                               "Focus on swing trades, 2-7 day holds, use wider stops"
                             when :options
                               "Focus on options buying, identify high probability setups, consider IV"
                             else
                               "General trading recommendations"
                             end

        <<~PROMPT
          Analyze the following technical analysis and provide trading recommendations:

          #{market_context}

          Trading Style: #{style_instructions}

          Provide:
          - Entry strategy
          - Stop loss levels
          - Target levels
          - Risk/reward ratio
          - Confidence level
        PROMPT
      end

      def build_analysis_schema
        {
          "type" => "object",
          "properties" => {
            "action" => { "type" => "string" },
            "reasoning" => { "type" => "string" }
          }
        }
      end

      def build_recommendation_schema(trading_style)
        {
          "type" => "object",
          "properties" => {
            "recommendation" => { "type" => "string", "enum" => ["buy", "sell", "hold", "avoid"] },
            "entry_price" => { "type" => "number" },
            "stop_loss" => { "type" => "number" },
            "target_price" => { "type" => "number" },
            "risk_reward_ratio" => { "type" => "number" },
            "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 },
            "reasoning" => { "type" => "string" },
            "timeframe" => { "type" => "string" }
          }
        }
      end
    end
  end
end

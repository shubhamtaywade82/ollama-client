# frozen_string_literal: true

require_relative "../utils/parameter_normalizer"
require_relative "../utils/parameter_cleaner"

module DhanHQ
  module Agents
    # Base class for all agents with common LLM interaction logic
    class BaseAgent
      MIN_CONFIDENCE = 0.6

      def initialize(ollama_client:, schema:)
        @ollama_client = ollama_client
        @schema = schema
      end

      def analyze_and_decide(market_context:)
        prompt = build_analysis_prompt(market_context: market_context)

        decision = call_llm(prompt)
        return invalid_decision unless valid_decision?(decision)

        decision = clean_parameters(decision)
        return low_confidence_decision(decision) if low_confidence?(decision)

        decision
      rescue Ollama::Error => e
        error_decision(e.message)
      rescue StandardError => e
        error_decision(e.message)
      end

      protected

      def build_analysis_prompt(market_context:)
        raise NotImplementedError, "Subclasses must implement build_analysis_prompt"
      end

      private

      def call_llm(prompt)
        @ollama_client.generate(prompt: prompt, schema: @schema)
      end

      def valid_decision?(decision)
        decision.is_a?(Hash) && decision["confidence"]
      end

      def clean_parameters(decision)
        return decision unless decision["parameters"].is_a?(Hash)

        cleaned_params = DhanHQ::Utils::ParameterCleaner.clean(decision["parameters"])
        decision.merge("parameters" => cleaned_params)
      end

      def low_confidence?(decision)
        decision["confidence"] < MIN_CONFIDENCE
      end

      def invalid_decision
        { action: "no_action", reason: "invalid_decision" }
      end

      def low_confidence_decision(decision)
        confidence_pct = (decision["confidence"] * 100).round
        puts "⚠️  Low confidence (#{confidence_pct}%) - skipping action"
        { action: "no_action", reason: "low_confidence" }
      end

      def error_decision(message)
        puts "❌ Ollama error: #{message}"
        { action: "no_action", reason: "error", error: message }
      end
    end
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Example: Multi-Step Agent with Complex Decision Making
# Demonstrates: Nested schemas, state management, error recovery, confidence thresholds

require "json"
require_relative "../lib/ollama_client"

class MultiStepAgent
  def initialize(client:)
    @client = client
    @state = {
      steps_completed: [],
      data_collected: {},
      errors: []
    }

    # Complex nested schema for decision making
    @decision_schema = {
      "type" => "object",
      "required" => ["step", "action", "reasoning", "confidence", "next_steps"],
      "properties" => {
        "step" => {
          "type" => "integer",
          "description" => "Current step number in the workflow"
        },
        "action" => {
          "type" => "object",
          "required" => ["type", "parameters"],
          "properties" => {
            "type" => {
              "type" => "string",
              "enum" => ["collect", "analyze", "transform", "validate", "complete"]
            },
            "parameters" => {
              "type" => "object",
              "additionalProperties" => true
            }
          }
        },
        "reasoning" => {
          "type" => "string",
          "description" => "Why this action was chosen"
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1
        },
        "next_steps" => {
          "type" => "array",
          "items" => {
            "type" => "string"
          },
          "minItems" => 0,
          "maxItems" => 5
        },
        "risk_assessment" => {
          "type" => "object",
          "properties" => {
            "level" => {
              "type" => "string",
              "enum" => ["low", "medium", "high"]
            },
            "factors" => {
              "type" => "array",
              "items" => { "type" => "string" }
            }
          }
        }
      }
    }
  end

  def execute_workflow(goal:)
    puts "🚀 Starting multi-step workflow"
    puts "Goal: #{goal}\n\n"

    max_steps = 10
    step_count = 0

    loop do
      step_count += 1
      break if step_count > max_steps

      puts "─" * 60
      puts "Step #{step_count}/#{max_steps}"
      puts "─" * 60

      context = build_context(goal: goal)

      begin
        decision = @client.generate(
          prompt: build_prompt(goal: goal, context: context),
          schema: @decision_schema
        )

        # Validate confidence threshold
        if decision["confidence"] < 0.5
          puts "⚠️  Low confidence (#{(decision["confidence"] * 100).round}%) - requesting manual review"
          break
        end

        display_decision(decision)
        result = execute_action(decision)

        # Update state
        @state[:steps_completed] << {
          step: decision["step"],
          action: decision["action"]["type"],
          result: result
        }

        # Check if workflow is complete
        if decision["action"]["type"] == "complete"
          puts "\n✅ Workflow completed successfully!"
          break
        end

        # Handle risk
        if decision["risk_assessment"] && decision["risk_assessment"]["level"] == "high"
          puts "⚠️  High risk detected - proceeding with caution"
        end

      rescue Ollama::SchemaViolationError => e
        puts "❌ Schema violation: #{e.message}"
        @state[:errors] << { step: step_count, error: "schema_violation", message: e.message }
        break
      rescue Ollama::RetryExhaustedError => e
        puts "❌ Retries exhausted: #{e.message}"
        @state[:errors] << { step: step_count, error: "retry_exhausted", message: e.message }
        break
      rescue Ollama::Error => e
        puts "❌ Error: #{e.message}"
        @state[:errors] << { step: step_count, error: "general", message: e.message }
        # Try to recover or break
        break if step_count > 3 # Don't loop forever
      end

      puts
      sleep 0.5 # Small delay for readability
    end

    display_summary
    @state
  end

  private

  def build_context(goal:)
    {
      steps_completed: @state[:steps_completed].map { |s| s[:action] },
      data_collected: @state[:data_collected].keys,
      error_count: @state[:errors].length
    }
  end

  def build_prompt(goal:, context:)
    <<~PROMPT
      Goal: #{goal}

      Workflow State:
      - Steps completed: #{context[:steps_completed].join(", ") || "none"}
      - Data collected: #{context[:data_collected].join(", ") || "none"}
      - Errors encountered: #{context[:error_count]}

      Analyze the current state and decide the next action.
      Consider:
      1. What data still needs to be collected?
      2. What analysis is needed?
      3. What validation is required?
      4. When should the workflow complete?

      Provide a structured decision with high confidence (>0.7) if possible.
    PROMPT
  end

  def display_decision(decision)
    puts "\n📋 Decision:"
    puts "   Step: #{decision['step']}"
    puts "   Action: #{decision['action']['type']}"
    puts "   Reasoning: #{decision['reasoning']}"
    puts "   Confidence: #{(decision['confidence'] * 100).round}%"
    if decision["risk_assessment"]
      puts "   Risk Level: #{decision['risk_assessment']['level']}"
      if decision["risk_assessment"]["factors"]
        puts "   Risk Factors: #{decision['risk_assessment']['factors'].join(', ')}"
      end
    end
    if decision["next_steps"] && !decision["next_steps"].empty?
      puts "   Next Steps: #{decision['next_steps'].join(' → ')}"
    end
  end

  def execute_action(decision)
    action_type = decision["action"]["type"]
    params = decision["action"]["parameters"] || {}

    case action_type
    when "collect"
      data_key = params["data_type"] || "unknown"
      puts "   📥 Collecting: #{data_key}"
      @state[:data_collected][data_key] = "collected_at_#{Time.now.to_i}"
      { status: "collected", key: data_key }

    when "analyze"
      target = params["target"] || "data"
      puts "   🔍 Analyzing: #{target}"
      { status: "analyzed", target: target, insights: "analysis_complete" }

    when "transform"
      transformation = params["type"] || "default"
      puts "   🔄 Transforming: #{transformation}"
      { status: "transformed", type: transformation }

    when "validate"
      validation_type = params["type"] || "general"
      puts "   ✓ Validating: #{validation_type}"
      { status: "validated", type: validation_type }

    when "complete"
      puts "   ✅ Completing workflow"
      { status: "complete" }

    else
      { status: "unknown_action" }
    end
  end

  def display_summary
    puts "\n" + "=" * 60
    puts "Workflow Summary"
    puts "=" * 60
    puts "Steps completed: #{@state[:steps_completed].length}"
    puts "Data collected: #{@state[:data_collected].keys.join(', ') || 'none'}"
    puts "Errors: #{@state[:errors].length}"
    if @state[:errors].any?
      puts "\nErrors:"
      @state[:errors].each do |error|
        puts "  Step #{error[:step]}: #{error[:error]} - #{error[:message]}"
      end
    end
  end
end

# Run example
if __FILE__ == $PROGRAM_NAME
  # Use longer timeout for multi-step workflows
  config = Ollama::Config.new
  config.timeout = 60 # 60 seconds for complex operations
  client = Ollama::Client.new(config: config)

  agent = MultiStepAgent.new(client: client)
  agent.execute_workflow(
    goal: "Collect user data, analyze patterns, validate results, and generate report"
  )
end


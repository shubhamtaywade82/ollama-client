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

        # Prevent infinite loops - if we've done the same action 3+ times, force progression
        recent_actions = @state[:steps_completed].last(3).map { |s| s[:action] }
        if recent_actions.length == 3 && recent_actions.uniq.length == 1
          puts "⚠️  Detected repetitive actions - forcing workflow progression"
          # Force next phase
          case recent_actions.first
          when "collect"
            puts "   → Moving to analysis phase"
            decision["action"]["type"] = "analyze"
            decision["action"]["parameters"] = { "target" => "collected_data" }
            result = execute_action(decision)
            @state[:steps_completed] << {
              step: decision["step"],
              action: "analyze",
              result: result
            }
          when "analyze"
            puts "   → Moving to validation phase"
            decision["action"]["type"] = "validate"
            decision["action"]["parameters"] = { "type" => "results" }
            result = execute_action(decision)
            @state[:steps_completed] << {
              step: decision["step"],
              action: "validate",
              result: result
            }
          when "validate"
            puts "   → Completing workflow"
            decision["action"]["type"] = "complete"
            result = execute_action(decision)
            @state[:steps_completed] << {
              step: decision["step"],
              action: "complete",
              result: result
            }
            puts "\n✅ Workflow completed successfully!"
            break
          end
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

  def build_context(goal:) # rubocop:disable Lint/UnusedMethodArgument
    {
      steps_completed: @state[:steps_completed].map { |s| s[:action] },
      data_collected: @state[:data_collected].keys,
      error_count: @state[:errors].length,
      step_count: @state[:steps_completed].length
    }
  end

  def build_prompt(goal:, context:)
    step_count = context[:step_count]
    completed_actions = context[:steps_completed]
    collected_data = context[:data_collected]

    # Determine current phase based on what's been done
    phase = if completed_actions.empty?
              "collection"
            elsif completed_actions.include?("collect") && !completed_actions.include?("analyze")
              "analysis"
            elsif completed_actions.include?("analyze") && !completed_actions.include?("validate")
              "validation"
            else
              "completion"
            end

    <<~PROMPT
      Goal: #{goal}

      Current Phase: #{phase}
      Steps completed: #{step_count}
      Actions taken: #{completed_actions.join(", ") || "none"}
      Data collected: #{collected_data.join(", ") || "none"}
      Errors encountered: #{context[:error_count]}

      Workflow Phases (in order):
      1. COLLECTION: Collect initial data (user data, patterns, etc.)
      2. ANALYSIS: Analyze collected data for patterns and insights
      3. VALIDATION: Validate the analysis results
      4. COMPLETION: Finish the workflow

      Current State Analysis:
      - You are in the #{phase} phase
      - You have completed #{step_count} steps
      - You have collected: #{collected_data.any? ? collected_data.join(", ") : "nothing yet"}

      Decision Guidelines:
      - If in COLLECTION phase and no data collected: use action "collect" with specific data_type (e.g., "user_data", "patterns")
      - If data collected but not analyzed: use action "analyze" with target
      - If analyzed but not validated: use action "validate"
      - If all phases done: use action "complete"
      - AVOID repeating the same action multiple times unless necessary
      - Progress through phases: collect → analyze → validate → complete

      Provide a structured decision with high confidence (>0.7) if possible.
      Set step number to #{step_count + 1}.
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
    return unless decision["next_steps"] && !decision["next_steps"].empty?

    puts "   Next Steps: #{decision['next_steps'].join(' → ')}"
  end

  def execute_action(decision)
    action_type = decision["action"]["type"]
    params = decision["action"]["parameters"] || {}

    case action_type
    when "collect"
      data_key = params["data_type"] || params["key"] || "user_data"
      # Prevent collecting the same generic data repeatedly
      if @state[:data_collected].key?(data_key) && data_key.match?(/^(missing|unknown|data)$/i) && !@state[:data_collected].key?("user_data")
        data_key = "user_data"
      end
      puts "   📥 Collecting: #{data_key}"
      @state[:data_collected][data_key] = "collected_at_#{Time.now.to_i}"
      { status: "collected", key: data_key }

    when "analyze"
      target = params["target"] || "collected_data"
      puts "   🔍 Analyzing: #{target}"
      # Mark that analysis has been done
      @state[:data_collected]["analysis_complete"] = true
      { status: "analyzed", target: target, insights: "Patterns identified in collected data" }

    when "transform"
      transformation = params["type"] || "default"
      puts "   🔄 Transforming: #{transformation}"
      { status: "transformed", type: transformation }

    when "validate"
      validation_type = params["type"] || "results"
      puts "   ✓ Validating: #{validation_type}"
      # Mark that validation has been done
      @state[:data_collected]["validation_complete"] = true
      { status: "validated", type: validation_type, result: "All checks passed" }

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
    return unless @state[:errors].any?

    puts "\nErrors:"
    @state[:errors].each do |error|
      puts "  Step #{error[:step]}: #{error[:error]} - #{error[:message]}"
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


#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete example showing how to use structured outputs in a real workflow
# This demonstrates the full cycle: schema definition -> LLM call -> using the result

require "json"
require_relative "../lib/ollama_client"

# Example: Task Planning Agent
# The LLM decides what action to take, and we execute it

class TaskPlanner
  def initialize(client:)
    @client = client
    @task_schema = {
      "type" => "object",
      "required" => ["action", "reasoning", "confidence", "next_step"],
      "properties" => {
        "action" => {
          "type" => "string",
          "description" => "The action to take",
          "enum" => ["search", "calculate", "store", "retrieve", "finish"]
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
        "next_step" => {
          "type" => "string",
          "description" => "What to do next"
        },
        "parameters" => {
          "type" => "object",
          "description" => "Parameters needed for the action"
        }
      }
    }
  end

  def plan(context:)
    puts "🤔 Planning next action..."
    puts "Context: #{context}\n\n"

    begin
      result = @client.generate(
        prompt: "Given this context: #{context}\n\nDecide the next action to take.",
        schema: @task_schema
      )

      # The result is guaranteed to match our schema
      display_decision(result)
      execute_action(result)

      result
    rescue Ollama::SchemaViolationError => e
      puts "❌ Invalid response structure: #{e.message}"
      puts "   This shouldn't happen with format parameter, but we handle it gracefully"
      nil
    rescue Ollama::Error => e
      puts "❌ Error: #{e.message}"
      nil
    end
  end

  private

  def display_decision(result)
    puts "📋 Decision:"
    puts "   Action: #{result['action']}"
    puts "   Reasoning: #{result['reasoning']}"
    puts "   Confidence: #{(result['confidence'] * 100).round}%"
    puts "   Next Step: #{result['next_step']}"
    puts "   Parameters: #{JSON.pretty_generate(result['parameters'] || {})}\n"
  end

  def execute_action(result)
    case result["action"]
    when "search"
      query = result.dig("parameters", "query") || "default"
      puts "🔍 Executing search: #{query}"
      # In real code, you'd call your search function here
      puts "   → Search results would appear here\n"

    when "calculate"
      operation = result.dig("parameters", "operation") || "unknown"
      puts "🧮 Executing calculation: #{operation}"
      # In real code, you'd call your calculator here
      puts "   → Calculation result would appear here\n"

    when "store"
      key = result.dig("parameters", "key") || "unknown"
      puts "💾 Storing data with key: #{key}"
      # In real code, you'd save to your storage
      puts "   → Data stored successfully\n"

    when "retrieve"
      key = result.dig("parameters", "key") || "unknown"
      puts "📂 Retrieving data with key: #{key}"
      # In real code, you'd fetch from your storage
      puts "   → Data retrieved successfully\n"

    when "finish"
      puts "✅ Task complete!\n"

    else
      puts "⚠️ Unknown action: #{result['action']}\n"
    end
  end
end

# Example: Data Analyzer
# The LLM analyzes data and returns structured insights

class DataAnalyzer
  def initialize(client:)
    @client = client
    @analysis_schema = {
      "type" => "object",
      "required" => ["summary", "confidence", "key_points"],
      "properties" => {
        "summary" => {
          "type" => "string",
          "description" => "Brief summary of the analysis"
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1
        },
        "key_points" => {
          "type" => "array",
          "items" => { "type" => "string" },
          "minItems" => 1,
          "maxItems" => 5
        },
        "sentiment" => {
          "type" => "string",
          "enum" => ["positive", "neutral", "negative"]
        },
        "recommendations" => {
          "type" => "array",
          "items" => { "type" => "string" }
        }
      }
    }
  end

  def analyze(data:)
    puts "📊 Analyzing data..."
    puts "Data: #{data}\n\n"

    begin
      result = @client.generate(
        prompt: "Analyze this data and provide insights: #{data}",
        schema: @analysis_schema
      )

      display_analysis(result)
      make_recommendations(result)

      result
    rescue Ollama::Error => e
      puts "❌ Error: #{e.message}"
      nil
    end
  end

  private

  def display_analysis(result)
    puts "📈 Analysis Results:"
    puts "   Summary: #{result['summary']}"
    puts "   Confidence: #{(result['confidence'] * 100).round}%"
    puts "   Sentiment: #{result['sentiment']}"
    puts "\n   Key Points:"
    result["key_points"].each_with_index do |point, i|
      puts "     #{i + 1}. #{point}"
    end

    if result["recommendations"] && !result["recommendations"].empty?
      puts "\n   Recommendations:"
      result["recommendations"].each_with_index do |rec, i|
        puts "     #{i + 1}. #{rec}"
      end
    end
    puts
  end

  def make_recommendations(result)
    if result["confidence"] > 0.8 && result["sentiment"] == "positive"
      puts "✅ High confidence positive analysis - safe to proceed"
    elsif result["confidence"] < 0.5
      puts "⚠️ Low confidence - manual review recommended"
    elsif result["sentiment"] == "negative"
      puts "⚠️ Negative sentiment detected - investigate further"
    end
    puts
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  client = Ollama::Client.new

  puts "=" * 60
  puts "Example 1: Task Planning Agent"
  puts "=" * 60
  puts

  planner = TaskPlanner.new(client: client)
  planner.plan(context: "User wants to know the weather in Paris")

  puts "\n" + "=" * 60
  puts "Example 2: Data Analysis"
  puts "=" * 60
  puts

  analyzer = DataAnalyzer.new(client: client)
  analyzer.analyze(
    data: "Sales increased 25% this quarter. Customer satisfaction is at 4.8/5. " \
          "Revenue: $1.2M. New customers: 150."
  )

  puts "=" * 60
  puts "Examples complete!"
  puts "=" * 60
end


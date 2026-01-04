#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Tool Calling Pattern (as documented in README)
# Demonstrates the correct architecture: LLM outputs intent, agent executes tools
# This matches the pattern shown in README.md lines 430-500

require "json"
require_relative "../lib/ollama_client"

# Tool Registry - stores available tools
class ToolRegistry
  def initialize
    @tools = {}
  end

  def register(name, tool)
    @tools[name] = tool
  end

  def fetch(name)
    @tools.fetch(name) { raise "Tool '#{name}' not found. Available: #{@tools.keys.join(', ')}" }
  end

  def available
    @tools.keys
  end
end

# Base Tool class
class Tool
  attr_reader :name, :description

  def initialize(name:, description:)
    @name = name
    @description = description
  end

  def call(input:, context:)
    raise NotImplementedError, "Subclass must implement #call"
  end
end

# Example Tools
class SearchTool < Tool
  def initialize
    super(name: "search", description: "Search for information")
  end

  def call(input:, context:)
    query = input["query"] || "default"
    # In real code, this would call your search API
    {
      query: query,
      results: [
        "Result 1 for: #{query}",
        "Result 2 for: #{query}",
        "Result 3 for: #{query}"
      ],
      count: 3
    }
  end
end

class CalculateTool < Tool
  def initialize
    super(name: "calculate", description: "Perform calculations")
  end

  def call(input:, context:)
    operation = input["operation"] || "add"
    a = input["a"] || 0
    b = input["b"] || 0

    result = case operation
             when "add" then a + b
             when "subtract" then a - b
             when "multiply" then a * b
             when "divide" then b.zero? ? "Error: Division by zero" : a / b
             else "Unknown operation: #{operation}"
             end

    {
      operation: operation,
      operands: { a: a, b: b },
      result: result
    }
  end
end

class StoreTool < Tool
  def initialize
    super(name: "store", description: "Store data")
    @storage = {}
  end

  def call(input:, context:)
    key = input["key"] || "default"
    value = input["value"] || {}
    @storage[key] = value

    {
      key: key,
      stored: true,
      message: "Data stored successfully"
    }
  end
end

# Tool Router - matches README example exactly
class ToolRouter
  def initialize(llm:, registry:)
    @llm = llm  # Ollama::Client instance
    @registry = registry
  end

  def step(prompt:, context: {})
    # LLM outputs intent (not execution)
    decision = @llm.generate(
      prompt: prompt,
      schema: {
        "type" => "object",
        "required" => ["action"],
        "properties" => {
          "action" => { "type" => "string" },
          "input" => { "type" => "object" }
        }
      }
    )

    return { done: true } if decision["action"] == "finish"

    # Agent executes tool (deterministic)
    tool = @registry.fetch(decision["action"])
    output = tool.call(input: decision["input"] || {}, context: context)

    { tool: tool.name, output: output }
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts "=" * 60
  puts "Tool Calling Pattern Example"
  puts "=" * 60
  puts

  # Setup
  client = Ollama::Client.new
  registry = ToolRegistry.new

  # Register tools
  registry.register("search", SearchTool.new)
  registry.register("calculate", CalculateTool.new)
  registry.register("store", StoreTool.new)

  # Create router
  router = ToolRouter.new(llm: client, registry: registry)

  puts "Available tools: #{registry.available.join(', ')}"
  puts

  # Example 1: Search
  puts "─" * 60
  puts "Example 1: Search Tool"
  puts "─" * 60
  begin
    result = router.step(
      prompt: "User wants to search for 'Ruby programming'. Use the search tool with query 'Ruby programming'.",
      context: {}
    )

    if result[:done]
      puts "✅ Workflow complete"
    else
      puts "Tool: #{result[:tool]}"
      puts "Output: #{JSON.pretty_generate(result[:output])}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  rescue StandardError => e
    puts "❌ Error: #{e.class}: #{e.message}"
  end

  puts

  # Example 2: Calculate
  puts "─" * 60
  puts "Example 2: Calculate Tool"
  puts "─" * 60
  begin
    result = router.step(
      prompt: "User wants to calculate 15 * 7. Use the calculate tool with operation 'multiply', a=15, b=7.",
      context: {}
    )

    if result[:done]
      puts "✅ Workflow complete"
    else
      puts "Tool: #{result[:tool]}"
      puts "Output: #{JSON.pretty_generate(result[:output])}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  rescue StandardError => e
    puts "❌ Error: #{e.class}: #{e.message}"
  end

  puts

  # Example 3: Store
  puts "─" * 60
  puts "Example 3: Store Tool"
  puts "─" * 60
  begin
    result = router.step(
      prompt: "User wants to store data with key 'user_preferences' and value {'theme': 'dark'}. Use the store tool.",
      context: {}
    )

    if result[:done]
      puts "✅ Workflow complete"
    else
      puts "Tool: #{result[:tool]}"
      puts "Output: #{JSON.pretty_generate(result[:output])}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  rescue StandardError => e
    puts "❌ Error: #{e.class}: #{e.message}"
  end

  puts

  # Example 4: Finish
  puts "─" * 60
  puts "Example 4: Finish Action"
  puts "─" * 60
  begin
    result = router.step(
      prompt: "The task is complete. Use action 'finish'.",
      context: {}
    )

    if result[:done]
      puts "✅ Workflow complete"
    else
      puts "Tool: #{result[:tool]}"
      puts "Output: #{JSON.pretty_generate(result[:output])}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  rescue StandardError => e
    puts "❌ Error: #{e.class}: #{e.message}"
  end

  puts
  puts "=" * 60
  puts "Pattern demonstrated:"
  puts "  1. LLM outputs structured intent (via ollama-client)"
  puts "  2. Agent validates and routes to tool"
  puts "  3. Tool executes deterministically (pure Ruby)"
  puts "  4. Results returned to agent"
  puts "=" * 60
end


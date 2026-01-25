#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using Personas for explicit, contextual personalization
#
# This demonstrates the correct way to inject personalization into Ollama-based systems:
# - Minimal agent-safe personas for schema-based planning (deterministic)
# - Minimal chat-safe personas for chat/streaming UI work (human-facing)
# - Persona selection per task without model changes
#
# Key principle: Personalization is a TOOL, not a background bias.
#
# CRITICAL SEPARATION:
# - Agent personas: /api/generate + schemas = deterministic reasoning
# - Chat personas: /api/chat + humans = explanatory conversation
# - NEVER mix them - it breaks determinism and safety boundaries.

require_relative "../lib/ollama_client"

# ============================================================================
# 1. Using Personas with Planner (schema-based agent work)
# ============================================================================

puts "=== 1. Planner with Architect Persona (Agent Variant) ===\n\n"

client = Ollama::Client.new

# Use compressed agent-safe persona for deterministic structured outputs
planner = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

decision_schema = {
  "type" => "object",
  "required" => ["action", "reasoning"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["refactor", "test", "document", "defer"]
    },
    "reasoning" => {
      "type" => "string"
    }
  }
}

plan = planner.run(
  prompt: "The method `calculateTotal` is 50 lines long and mixes calculation with formatting. What should we do?",
  schema: decision_schema
)

puts "Decision: #{plan.inspect}\n\n"

# ============================================================================
# 2. Using Personas with Executor (tool-calling agent work)
# ============================================================================

puts "=== 2. Executor with Trading Persona ===\n\n"

tools = {
  "get_price" => ->(symbol:) { { symbol: symbol, price: 150.25, volume: 1_000_000 } },
  "get_indicators" => ->(symbol:) { { symbol: symbol, rsi: 65.5, macd: 1.2 } }
}

# Use compressed agent-safe persona for tool-calling agents
executor = Ollama::Agent::Executor.new(
  client,
  tools: tools
)

answer = executor.run(
  system: Ollama::Personas.get(:trading, variant: :agent),
  user: "Analyze AAPL. Get current price and technical indicators."
)

puts "Analysis: #{answer}\n\n"

# ============================================================================
# 3. Using Personas with ChatSession (human-facing chat)
# ============================================================================

puts "=== 3. ChatSession with Architect Persona (Chat Variant) ===\n\n"

# Enable chat in config (required for ChatSession)
config = Ollama::Config.new
config.allow_chat = true
config.streaming_enabled = true

chat_client = Ollama::Client.new(config: config)

# Create streaming observer for real-time token display
observer = Ollama::StreamingObserver.new do |event|
  case event.type
  when :token
    print event.text
    $stdout.flush
  when :final
    puts "\n"
  end
end

# Use MINIMAL CHAT-SAFE persona for human-facing chat interfaces
# This allows explanations and streaming while preventing hallucination
# and explicitly disclaiming authority and side effects.
chat = Ollama::ChatSession.new(
  chat_client,
  system: Ollama::Personas.get(:architect, variant: :chat),
  stream: observer
)

puts "Chat example:\n"
puts "You: How should I structure a multi-agent system?\n"
puts "Assistant: "
chat.say("How should I structure a multi-agent system?")
puts "\n"

# ============================================================================
# 3b. ChatSession with Trading Persona (showing different persona)
# ============================================================================

puts "=== 3b. ChatSession with Trading Persona (Chat Variant) ===\n\n"

# Create a new chat session with trading persona
trading_chat = Ollama::ChatSession.new(
  chat_client,
  system: Ollama::Personas.get(:trading, variant: :chat),
  stream: observer
)

puts "Chat example:\n"
puts "You: Explain how to assess market risk for a portfolio.\n"
puts "Assistant: "
trading_chat.say("Explain how to assess market risk for a portfolio.")
puts "\n"

# ============================================================================
# 4. Persona Registry and Selection
# ============================================================================

puts "=== 4. Persona Registry ===\n\n"

puts "Available personas: #{Ollama::Personas.available.inspect}"
puts "\n"

# Check if persona exists
puts "Architect persona exists: #{Ollama::Personas.exists?(:architect)}"
puts "Trading persona exists: #{Ollama::Personas.exists?(:trading)}"
puts "Reviewer persona exists: #{Ollama::Personas.exists?(:reviewer)}"
puts "Unknown persona exists: #{Ollama::Personas.exists?(:unknown)}"
puts "\n"

# ============================================================================
# 5. Dynamic Persona Selection
# ============================================================================

puts "=== 5. Dynamic Persona Selection ===\n\n"

def select_persona_for_task(task_type)
  case task_type
  when :planning, :architecture
    Ollama::Personas.get(:architect, variant: :agent)
  when :trading, :analysis
    Ollama::Personas.get(:trading, variant: :agent)
  when :review, :refactor
    Ollama::Personas.get(:reviewer, variant: :agent)
  else
    nil
  end
end

# Use persona based on task type
task_persona = select_persona_for_task(:planning)
planner_with_persona = Ollama::Agent::Planner.new(client, system_prompt: task_persona)

plan = planner_with_persona.run(
  prompt: "Design a caching layer for a high-traffic API.",
  schema: {
    "type" => "object",
    "required" => ["approach"],
    "properties" => {
      "approach" => { "type" => "string" }
    }
  }
)

puts "Plan with dynamic persona: #{plan.inspect}\n\n"

# ============================================================================
# 6. Per-Call Persona Override
# ============================================================================

puts "=== 6. Per-Call Persona Override ===\n\n"

# Planner with default persona
planner_default = Ollama::Agent::Planner.new(
  client,
  system_prompt: Ollama::Personas.get(:architect, variant: :agent)
)

# Override persona for specific call
plan = planner_default.run(
  prompt: "Review this code for maintainability issues.",
  schema: {
    "type" => "object",
    "required" => ["issues"],
    "properties" => {
      "issues" => { "type" => "array", "items" => { "type" => "string" } }
    }
  },
  system_prompt: Ollama::Personas.get(:reviewer, variant: :agent)
)

puts "Review with overridden persona: #{plan.inspect}\n\n"

# ============================================================================
# 7. What NOT to Do (Critical Separation)
# ============================================================================

puts "=== 7. What NOT to Do ===\n\n"

puts "❌ DO NOT use chat personas for agent work:"
puts "   planner.run(prompt: ..., schema: ..., system_prompt: Personas.get(:architect, :chat))"
puts "   This breaks determinism and schema enforcement.\n"

puts "❌ DO NOT use agent personas for chat:"
puts "   chat = ChatSession.new(client, system: Personas.get(:architect, :agent))"
puts "   This suppresses explanations and makes chat feel robotic.\n"

puts "✅ DO use agent personas for /api/generate with schemas"
puts "✅ DO use chat personas for /api/chat with ChatSession"
puts "✅ DO keep them separate - they serve different purposes\n"

puts "=== Example Complete ===\n"
puts "\nKey Takeaways:"
puts "1. Use minimal :agent variants for schema-based work (deterministic)"
puts "2. Use minimal :chat variants for human-facing interfaces (explanatory)"
puts "3. Personas are explicit, not implicit - you control when they apply"
puts "4. Switch personas per task without model changes"
puts "5. NEVER mix agent and chat personas - they have different contracts"
puts "6. This is architecturally superior to ChatGPT's global personalization"

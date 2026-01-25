#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Example: Comprehensive Error Handling and Recovery Patterns
# Demonstrates: All error types, retry strategies, fallback mechanisms, observability

require "json"
require_relative "../lib/ollama_client"

class ResilientAgent
  def initialize(client:)
    @client = client
    @stats = {
      total_calls: 0,
      successes: 0,
      retries: 0,
      failures: 0,
      errors_by_type: {}
    }
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def execute_with_resilience(prompt:, schema:, max_attempts: 3)
    @stats[:total_calls] += 1
    attempt = 0

    loop do
      attempt += 1
      puts "\n📞 Attempt #{attempt}/#{max_attempts}"

      begin
        result = @client.generate(prompt: prompt, schema: schema)
        @stats[:successes] += 1
        puts "✅ Success on attempt #{attempt}"
        return { success: true, result: result, attempts: attempt }
      rescue Ollama::NotFoundError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["NotFoundError"] ||= 0
        @stats[:errors_by_type]["NotFoundError"] += 1

        puts "❌ Model not found: #{e.message}"
        puts "   Suggestions: #{e.suggestions.join(', ')}" if e.suggestions && !e.suggestions.empty?
        # Don't retry 404s
        return { success: false, error: e, error_type: "NotFoundError", attempts: attempt }
      rescue Ollama::HTTPError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["HTTPError"] ||= 0
        @stats[:errors_by_type]["HTTPError"] += 1

        puts "❌ HTTP Error (#{e.status_code}): #{e.message}"
        if e.retryable?
          @stats[:retries] += 1
          puts "   → Retryable, will retry..."
          if attempt > max_attempts
            return { success: false, error: e, error_type: "HTTPError", retryable: true,
                     attempts: attempt }
          end

          sleep(2**attempt) # Exponential backoff
          next
        else
          puts "   → Non-retryable, aborting"
          return { success: false, error: e, error_type: "HTTPError", retryable: false, attempts: attempt }
        end
      rescue Ollama::TimeoutError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["TimeoutError"] ||= 0
        @stats[:errors_by_type]["TimeoutError"] += 1

        puts "⏱️  Timeout: #{e.message}"
        @stats[:retries] += 1
        return { success: false, error: e, error_type: "TimeoutError", attempts: attempt } unless attempt < max_attempts

        puts "   → Retrying with exponential backoff..."
        sleep(2**attempt)
        next
      rescue Ollama::SchemaViolationError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["SchemaViolationError"] ||= 0
        @stats[:errors_by_type]["SchemaViolationError"] += 1

        puts "🔴 Schema violation: #{e.message}"
        # Schema violations are usually not worth retrying (model issue)
        # But we could try with a simpler schema as fallback
        unless attempt < max_attempts
          return { success: false, error: e, error_type: "SchemaViolationError", attempts: attempt }
        end

        puts "   → Attempting with simplified schema..."
        simplified_schema = create_fallback_schema(schema)
        return execute_with_resilience(
          prompt: prompt,
          schema: simplified_schema,
          max_attempts: 1
        )
      rescue Ollama::InvalidJSONError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["InvalidJSONError"] ||= 0
        @stats[:errors_by_type]["InvalidJSONError"] += 1

        puts "📄 Invalid JSON: #{e.message}"
        @stats[:retries] += 1
        unless attempt < max_attempts
          return { success: false, error: e, error_type: "InvalidJSONError", attempts: attempt }
        end

        puts "   → Retrying..."
        sleep(1)
        next
      rescue Ollama::RetryExhaustedError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["RetryExhaustedError"] ||= 0
        @stats[:errors_by_type]["RetryExhaustedError"] += 1

        puts "🔄 Retries exhausted: #{e.message}"
        return { success: false, error: e, error_type: "RetryExhaustedError", attempts: attempt }
      rescue Ollama::Error => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["Error"] ||= 0
        @stats[:errors_by_type]["Error"] += 1

        puts "❌ General error: #{e.message}"
        return { success: false, error: e, error_type: "Error", attempts: attempt }
      rescue StandardError => e
        @stats[:failures] += 1
        @stats[:errors_by_type]["StandardError"] ||= 0
        @stats[:errors_by_type]["StandardError"] += 1

        puts "💥 Unexpected error: #{e.class}: #{e.message}"
        return { success: false, error: e, error_type: "StandardError", attempts: attempt }
      end
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def create_fallback_schema(_original_schema)
    # Create a minimal fallback schema
    {
      "type" => "object",
      "additionalProperties" => true
    }
  end

  def display_stats
    puts "\n" + "=" * 60
    puts "Execution Statistics"
    puts "=" * 60
    puts "Total calls: #{@stats[:total_calls]}"
    puts "Successes: #{@stats[:successes]}"
    puts "Failures: #{@stats[:failures]}"
    puts "Retries: #{@stats[:retries]}"
    success_rate = @stats[:total_calls].positive? ? (@stats[:successes].to_f / @stats[:total_calls] * 100).round(2) : 0
    puts "Success rate: #{success_rate}%"
    puts "\nErrors by type:"
    @stats[:errors_by_type].each do |type, count|
      puts "  #{type}: #{count}"
    end
  end
end

# Test scenarios
if __FILE__ == $PROGRAM_NAME
  # Load .env file if available
  begin
    require "dotenv"
    Dotenv.overload
  rescue LoadError
    # dotenv not available, skip
  end

  config = Ollama::Config.new
  config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", config.model)
  client = Ollama::Client.new(config: config)
  agent = ResilientAgent.new(client: client)

  schema = {
    "type" => "object",
    "required" => ["status", "message"],
    "properties" => {
      "status" => { "type" => "string" },
      "message" => { "type" => "string" }
    }
  }

  puts "=" * 60
  puts "Test 1: Normal execution"
  puts "=" * 60
  result1 = agent.execute_with_resilience(
    prompt: "Respond with status 'ok' and a greeting message",
    schema: schema
  )
  puts "Result: #{result1[:success] ? 'SUCCESS' : 'FAILED'}"

  puts "\n" + "=" * 60
  puts "Test 2: Invalid model (should trigger NotFoundError)"
  puts "=" * 60
  # Temporarily use invalid model
  invalid_client = Ollama::Client.new(
    config: Ollama::Config.new.tap { |c| c.model = "nonexistent-model:999" }
  )
  invalid_agent = ResilientAgent.new(client: invalid_client)
  result2 = invalid_agent.execute_with_resilience(
    prompt: "Test",
    schema: schema
  )
  puts "Result: #{result2[:success] ? 'SUCCESS' : 'FAILED'}"

  agent.display_stats
end


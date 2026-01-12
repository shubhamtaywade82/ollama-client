#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Example: Edge Cases and Boundary Testing
# Demonstrates: Empty responses, malformed schemas, extreme values, special characters

require "json"
require_relative "../lib/ollama_client"

class EdgeCaseTester
  def initialize(client:)
    @client = client
  end

  def test_empty_prompt
    puts "Test 1: Empty prompt"
    schema = {
      "type" => "object",
      "properties" => {
        "response" => { "type" => "string" }
      }
    }

    begin
      result = @client.generate(prompt: "", schema: schema)
      puts "  ✅ Handled empty prompt: #{result.inspect[0..100]}"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_very_long_prompt
    puts "Test 2: Very long prompt (10KB+)"
    long_prompt = "Repeat this sentence. " * 500
    schema = {
      "type" => "object",
      "properties" => {
        "summary" => { "type" => "string" }
      }
    }

    begin
      @client.generate(prompt: long_prompt, schema: schema)
      puts "  ✅ Handled long prompt (#{long_prompt.length} chars)"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_special_characters
    puts "Test 3: Special characters in prompt"
    special_prompt = "Analyze: !@#$%^&*()_+-=[]{}|;':\",./<>?`~"
    schema = {
      "type" => "object",
      "properties" => {
        "analysis" => { "type" => "string" }
      }
    }

    begin
      @client.generate(prompt: special_prompt, schema: schema)
      puts "  ✅ Handled special characters"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_unicode_characters
    puts "Test 4: Unicode characters"
    unicode_prompt = "Analyze: 你好世界 🌍 🚀 émojis and spéciál chäracters"
    schema = {
      "type" => "object",
      "properties" => {
        "analysis" => { "type" => "string" }
      }
    }

    begin
      @client.generate(prompt: unicode_prompt, schema: schema)
      puts "  ✅ Handled unicode characters"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_minimal_schema
    puts "Test 5: Minimal schema (no required fields)"
    schema = {
      "type" => "object",
      "additionalProperties" => true
    }

    begin
      result = @client.generate(
        prompt: "Return any JSON object",
        schema: schema
      )
      puts "  ✅ Handled minimal schema: #{result.keys.join(', ')}"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_strict_schema
    puts "Test 6: Strict schema with many constraints"
    strict_schema = {
      "type" => "object",
      "required" => ["id", "name", "values"],
      "properties" => {
        "id" => {
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 1000
        },
        "name" => {
          "type" => "string",
          "minLength" => 3,
          "maxLength" => 20,
          "pattern" => "^[A-Za-z0-9_]+$"
        },
        "values" => {
          "type" => "array",
          "minItems" => 2,
          "maxItems" => 5,
          "items" => {
            "type" => "number",
            "minimum" => 0,
            "maximum" => 100
          }
        }
      }
    }

    begin
      prompt_text = "Generate a valid object with id (1-1000), " \
                    "name (3-20 alphanumeric chars), " \
                    "and values (2-5 numbers 0-100)"
      result = @client.generate(
        prompt: prompt_text,
        schema: strict_schema
      )
      puts "  ✅ Handled strict schema"
      puts "     ID: #{result['id']}, Name: #{result['name']}, Values: #{result['values']}"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_nested_arrays
    puts "Test 7: Deeply nested arrays"
    nested_schema = {
      "type" => "object",
      "properties" => {
        "matrix" => {
          "type" => "array",
          "items" => {
            "type" => "array",
            "items" => {
              "type" => "array",
              "items" => { "type" => "integer" }
            }
          }
        }
      }
    }

    begin
      @client.generate(
        prompt: "Generate a 2x2x2 matrix of integers",
        schema: nested_schema
      )
      puts "  ✅ Handled nested arrays"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def test_enum_constraints
    puts "Test 8: Strict enum constraints"
    enum_schema = {
      "type" => "object",
      "required" => ["status", "priority"],
      "properties" => {
        "status" => {
          "type" => "string",
          "enum" => ["pending", "in_progress", "completed", "failed"]
        },
        "priority" => {
          "type" => "string",
          "enum" => ["low", "medium", "high", "urgent"]
        }
      }
    }

    begin
      result = @client.generate(
        prompt: "Choose a status and priority from the allowed values",
        schema: enum_schema
      )
      puts "  ✅ Handled enum constraints: status=#{result['status']}, priority=#{result['priority']}"
    rescue Ollama::Error => e
      puts "  ❌ Error: #{e.class} - #{e.message}"
    end
    puts
  end

  def run_all_tests
    puts "=" * 60
    puts "Edge Case Testing Suite"
    puts "=" * 60
    puts

    test_empty_prompt
    test_very_long_prompt
    test_special_characters
    test_unicode_characters
    test_minimal_schema
    test_strict_schema
    test_nested_arrays
    test_enum_constraints

    puts "=" * 60
    puts "Edge case testing complete!"
    puts "=" * 60
  end
end

# Run tests
if __FILE__ == $PROGRAM_NAME
  client = Ollama::Client.new
  tester = EdgeCaseTester.new(client: client)
  tester.run_all_tests
end


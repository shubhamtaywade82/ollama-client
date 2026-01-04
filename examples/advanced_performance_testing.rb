#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Example: Performance Testing and Observability
# Demonstrates: Latency measurement, throughput testing, error rate tracking, concurrent requests

require "json"
require "benchmark"
require "time"
require_relative "../lib/ollama_client"

class PerformanceMonitor
  def initialize(client:)
    @client = client
    @metrics = {
      calls: [],
      errors: [],
      latencies: []
    }
  end

  def measure_call(prompt:, schema:)
    start_time = Time.now

    begin
      result = @client.generate(prompt: prompt, schema: schema)
      latency = (Time.now - start_time) * 1000 # Convert to milliseconds

      @metrics[:calls] << {
        success: true,
        latency_ms: latency,
        timestamp: Time.now.iso8601
      }
      @metrics[:latencies] << latency

      { success: true, result: result, latency_ms: latency }
    rescue Ollama::Error => e
      latency = (Time.now - start_time) * 1000
      @metrics[:calls] << {
        success: false,
        latency_ms: latency,
        error: e.class.name,
        timestamp: Time.now.iso8601
      }
      @metrics[:errors] << { error: e.class.name, message: e.message, latency_ms: latency }

      { success: false, error: e, latency_ms: latency }
    end
  end

  def run_throughput_test(prompt:, schema:, iterations: 10)
    puts "🚀 Running throughput test (#{iterations} iterations)..."
    results = []

    total_time = Benchmark.realtime do
      iterations.times do |i|
        print "  #{i + 1}/#{iterations}... "
        result = measure_call(prompt: prompt, schema: schema)
        results << result
        puts result[:success] ? "✓" : "✗"
      end
    end

    {
      total_time: total_time,
      iterations: iterations,
      throughput: iterations / total_time,
      results: results
    }
  end

  def run_latency_test(prompt:, schema:, iterations: 10)
    puts "⏱️  Running latency test (#{iterations} iterations)..."
    latencies = []

    iterations.times do |i|
      print "  #{i + 1}/#{iterations}... "
      result = measure_call(prompt: prompt, schema: schema)
      if result[:success]
        latencies << result[:latency_ms]
        puts "#{result[:latency_ms].round(2)}ms"
      else
        puts "ERROR"
      end
    end

    {
      latencies: latencies,
      min: latencies.min,
      max: latencies.max,
      avg: latencies.sum / latencies.length,
      median: latencies.sort[latencies.length / 2],
      p95: latencies.sort[(latencies.length * 0.95).to_i],
      p99: latencies.sort[(latencies.length * 0.99).to_i]
    }
  end

  def display_metrics
    puts "\n" + "=" * 60
    puts "Performance Metrics"
    puts "=" * 60

    total_calls = @metrics[:calls].length
    successful = @metrics[:calls].count { |c| c[:success] }
    failed = total_calls - successful

    puts "Total calls: #{total_calls}"
    puts "Successful: #{successful} (#{(successful.to_f / total_calls * 100).round(2)}%)"
    puts "Failed: #{failed} (#{(failed.to_f / total_calls * 100).round(2)}%)"

    if @metrics[:latencies].any?
      latencies = @metrics[:latencies]
      puts "\nLatency Statistics (ms):"
      puts "  Min: #{latencies.min.round(2)}"
      puts "  Max: #{latencies.max.round(2)}"
      puts "  Avg: #{(latencies.sum / latencies.length).round(2)}"
      puts "  Median: #{latencies.sort[latencies.length / 2].round(2)}"
      puts "  P95: #{latencies.sort[(latencies.length * 0.95).to_i].round(2)}"
      puts "  P99: #{latencies.sort[(latencies.length * 0.99).to_i].round(2)}"
    end

    if @metrics[:errors].any?
      puts "\nErrors by type:"
      error_counts = @metrics[:errors].group_by { |e| e[:error] }
      error_counts.each do |error_type, errors|
        puts "  #{error_type}: #{errors.length}"
      end
    end
  end

  def export_metrics(filename: "metrics.json")
    File.write(filename, JSON.pretty_generate(@metrics))
    puts "\n📊 Metrics exported to #{filename}"
  end
end

# Run performance tests
if __FILE__ == $PROGRAM_NAME
  # Use longer timeout for performance testing
  config = Ollama::Config.new
  config.timeout = 60 # 60 seconds for complex operations
  client = Ollama::Client.new(config: config)
  monitor = PerformanceMonitor.new(client: client)

  schema = {
    "type" => "object",
    "required" => ["response"],
    "properties" => {
      "response" => { "type" => "string" }
    }
  }

  puts "=" * 60
  puts "Performance Testing Suite"
  puts "=" * 60

  # Test 1: Latency
  latency_results = monitor.run_latency_test(
    prompt: "Respond with a simple acknowledgment",
    schema: schema,
    iterations: 5
  )

  puts "\nLatency Results:"
  puts "  Average: #{latency_results[:avg].round(2)}ms"
  puts "  P95: #{latency_results[:p95].round(2)}ms"
  puts "  P99: #{latency_results[:p99].round(2)}ms"

  # Test 2: Throughput
  throughput_results = monitor.run_throughput_test(
    prompt: "Count to 5",
    schema: schema,
    iterations: 5
  )

  puts "\nThroughput Results:"
  puts "  Total time: #{throughput_results[:total_time].round(2)}s"
  puts "  Throughput: #{throughput_results[:throughput].round(2)} calls/sec"

  # Display all metrics
  monitor.display_metrics

  # Export metrics
  monitor.export_metrics
end


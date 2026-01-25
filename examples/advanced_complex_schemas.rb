#!/usr/bin/env ruby
# frozen_string_literal: true

# Advanced Example: Complex Nested Schemas and Validation
# Demonstrates: Deep nesting, arrays of objects, conditional validation, real-world data structures

require "json"
require_relative "../lib/ollama_client"

# Example 1: Financial Analysis Schema
class FinancialAnalyzer
  def initialize(client:)
    @client = client
    @schema = {
      "type" => "object",
      "required" => ["analysis_date", "summary", "metrics", "recommendations"],
      "properties" => {
        "analysis_date" => {
          "type" => "string",
          "format" => "date-time"
        },
        "summary" => {
          "type" => "string",
          "minLength" => 50,
          "maxLength" => 500
        },
        "metrics" => {
          "type" => "object",
          "required" => ["revenue", "profit_margin", "growth_rate"],
          "properties" => {
            "revenue" => {
              "type" => "number",
              "minimum" => 0
            },
            "profit_margin" => {
              "type" => "number",
              "minimum" => 0,
              "maximum" => 100,
              "description" => "Profit margin as percentage (0 to 100)"
            },
            "growth_rate" => {
              "type" => "number"
            },
            "trend" => {
              "type" => "string",
              "enum" => ["increasing", "stable", "decreasing"]
            }
          }
        },
        "recommendations" => {
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 10,
          "items" => {
            "type" => "object",
            "required" => ["action", "priority", "rationale"],
            "properties" => {
              "action" => {
                "type" => "string"
              },
              "priority" => {
                "type" => "string",
                "enum" => ["low", "medium", "high", "critical"]
              },
              "rationale" => {
                "type" => "string"
              },
              "estimated_impact" => {
                "type" => "object",
                "properties" => {
                  "revenue_impact" => {
                    "type" => "number"
                  },
                  "risk_level" => {
                    "type" => "string",
                    "enum" => ["low", "medium", "high"]
                  }
                }
              }
            }
          }
        },
        "risk_factors" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => ["factor", "severity"],
            "properties" => {
              "factor" => { "type" => "string" },
              "severity" => {
                "type" => "string",
                "enum" => ["low", "medium", "high", "critical"]
              },
              "mitigation" => { "type" => "string" }
            }
          }
        }
      }
    }
  end

  def analyze(data:)
    prompt = <<~PROMPT
      Analyze this financial data: #{data}

      Return JSON with: summary (50-500 chars), metrics (revenue, profit_margin, growth_rate, trend),
      recommendations array (action, priority, rationale), and optional risk_factors array.
    PROMPT

    @client.generate(prompt: prompt, schema: @schema)
  end
end

# Example 2: Code Review Schema
class CodeReviewer
  def initialize(client:)
    @client = client
    @schema = {
      "type" => "object",
      "required" => ["overall_score", "issues", "suggestions"],
      "properties" => {
        "overall_score" => {
          "type" => "integer",
          "minimum" => 0,
          "maximum" => 100,
          "description" => "Overall quality score (0 to 100)"
        },
        "issues" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => ["type", "severity", "location", "description"],
            "properties" => {
              "type" => {
                "type" => "string",
                "enum" => ["bug", "security", "performance", "style", "maintainability"]
              },
              "severity" => {
                "type" => "string",
                "enum" => ["low", "medium", "high", "critical"]
              },
              "location" => {
                "type" => "object",
                "properties" => {
                  "file" => { "type" => "string" },
                  "line" => { "type" => "integer" },
                  "column" => { "type" => "integer" }
                }
              },
              "description" => { "type" => "string" },
              "suggestion" => { "type" => "string" }
            }
          }
        },
        "suggestions" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => ["category", "description"],
            "properties" => {
              "category" => {
                "type" => "string",
                "enum" => ["refactoring", "optimization", "documentation", "testing"]
              },
              "description" => { "type" => "string" },
              "priority" => {
                "type" => "string",
                "enum" => ["low", "medium", "high"]
              }
            }
          }
        },
        "strengths" => {
          "type" => "array",
          "items" => { "type" => "string" }
        },
        "estimated_effort" => {
          "type" => "object",
          "properties" => {
            "hours" => { "type" => "number", "minimum" => 0 },
            "complexity" => {
              "type" => "string",
              "enum" => ["simple", "moderate", "complex"]
            }
          }
        }
      }
    }
  end

  def review(code:)
    prompt = <<~PROMPT
      Review this Ruby code: #{code}

      Return JSON with: overall_score (0-100), issues array (type, severity, location, description),
      suggestions array (category, description, priority), optional strengths array, optional estimated_effort.
    PROMPT

    @client.generate(prompt: prompt, schema: @schema)
  end
end

# Example 3: Research Paper Analysis Schema
class ResearchAnalyzer
  def initialize(client:)
    @client = client
    @schema = {
      "type" => "object",
      "required" => ["title", "key_findings", "methodology", "citations"],
      "properties" => {
        "title" => { "type" => "string" },
        "key_findings" => {
          "type" => "array",
          "minItems" => 3,
          "maxItems" => 10,
          "items" => {
            "type" => "object",
            "required" => ["finding", "significance"],
            "properties" => {
              "finding" => { "type" => "string" },
              "significance" => {
                "type" => "string",
                "enum" => ["low", "medium", "high", "breakthrough"]
              },
              "evidence" => { "type" => "string" }
            }
          }
        },
        "methodology" => {
          "type" => "object",
          "required" => ["type", "description"],
          "properties" => {
            "type" => {
              "type" => "string",
              "enum" => ["experimental", "observational", "theoretical", "computational", "mixed"]
            },
            "description" => { "type" => "string" },
            "limitations" => {
              "type" => "array",
              "items" => { "type" => "string" }
            }
          }
        },
        "citations" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => ["author", "title", "year"],
            "properties" => {
              "author" => { "type" => "string" },
              "title" => { "type" => "string" },
              "year" => {
                "type" => "integer",
                "minimum" => 1900,
                "maximum" => 2100
              },
              "relevance" => {
                "type" => "string",
                "enum" => ["low", "medium", "high"]
              }
            }
          }
        },
        "reproducibility_score" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Reproducibility score (0.0 to 1.0, where 1.0 means fully reproducible)"
        }
      }
    }
  end

  def analyze(paper_text:)
    prompt = <<~PROMPT
      Analyze this research paper: #{paper_text}

      Return JSON with: title, key_findings array (3-10 items: finding, significance, evidence),
      methodology (type, description, limitations), citations array (author, title, year, relevance),
      optional reproducibility_score (0-1).
    PROMPT

    @client.generate(prompt: prompt, schema: @schema)
  end
end

# Run examples
if __FILE__ == $PROGRAM_NAME
  # Load .env file if available
  begin
    require "dotenv"
    Dotenv.overload
  rescue LoadError
    # dotenv not available, skip
  end

  # Use longer timeout for complex schemas
  config = Ollama::Config.new
  config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  config.model = ENV.fetch("OLLAMA_MODEL", config.model)
  config.timeout = 60 # 60 seconds for complex operations
  client = Ollama::Client.new(config: config)

  puts "=" * 60
  puts "Example 1: Financial Analysis"
  puts "=" * 60
  financial_data = <<~DATA
    Q4 2024 Financial Report:
    - Revenue: $2.5M (up 15% from Q3)
    - Operating expenses: $1.8M
    - Net profit: $700K
    - Customer base: 5,000 (up 20%)
    - Churn rate: 2% (down from 3%)
  DATA

  analyzer = FinancialAnalyzer.new(client: client)
  begin
    puts "⏳ Analyzing financial data (this may take 30-60 seconds)..."
    result = analyzer.analyze(data: financial_data)
    puts JSON.pretty_generate(result)
  rescue Ollama::TimeoutError => e
    puts "⏱️  Timeout: #{e.message}"
    puts "   Try increasing timeout or using a faster model"
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts "\n" + "=" * 60
  puts "Example 2: Code Review"
  puts "=" * 60
  code_sample = <<~RUBY
    def calculate_total(items)
      total = 0
      items.each do |item|
        total += item.price
      end
      total
    end
  RUBY

  reviewer = CodeReviewer.new(client: client)
  begin
    puts "⏳ Reviewing code (this may take 30-60 seconds)..."
    result = reviewer.review(code: code_sample)
    puts JSON.pretty_generate(result)
  rescue Ollama::TimeoutError => e
    puts "⏱️  Timeout: #{e.message}"
    puts "   Try increasing timeout or using a faster model"
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts "\n" + "=" * 60
  puts "Example 3: Research Paper Analysis"
  puts "=" * 60
  paper_abstract = <<~TEXT
    This study investigates the impact of machine learning on financial forecasting.
    We analyzed 10 years of market data using neural networks and found a 23% improvement
    in prediction accuracy. The methodology involved training on historical data and
    validating on out-of-sample periods. Key limitations include data quality and
    model interpretability challenges.
  TEXT

  research_analyzer = ResearchAnalyzer.new(client: client)
  begin
    puts "⏳ Analyzing research paper (this may take 30-60 seconds)..."
    result = research_analyzer.analyze(paper_text: paper_abstract)
    puts JSON.pretty_generate(result)
  rescue Ollama::TimeoutError => e
    puts "⏱️  Timeout: #{e.message}"
    puts "   Try increasing timeout or using a faster model"
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end
end


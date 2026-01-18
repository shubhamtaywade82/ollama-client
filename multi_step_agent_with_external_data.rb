#!/usr/bin/env ruby
# frozen_string_literal: true

# Use local code instead of installed gem
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "ollama_client"
require "json"
require "fileutils"

puts "\n=== MULTI-STEP AGENT WITH EXTERNAL DATA TEST ===\n"

# Configuration via environment variables (defaults for local testing)
BASE_URL = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")

def client_for(model:, temperature:, timeout:)
  config = Ollama::Config.new
  config.base_url = BASE_URL
  config.model = model
  config.temperature = temperature
  config.timeout = timeout
  config.retries = 2
  Ollama::Client.new(config: config)
end

# ------------------------------------------------------------
# PLANNER SETUP (STATELESS)
# ------------------------------------------------------------

planner_client = client_for(
  model: ENV.fetch("OLLAMA_MODEL", "llama3.1:8b"),
  temperature: 0,
  timeout: 40
)

planner = Ollama::Agent::Planner.new(planner_client)

decision_schema = {
  "type" => "object",
  "required" => %w[action reason],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => %w[read_file read_reference analyze_with_reference finish]
    },
    "reason" => { "type" => "string" }
  }
}

# ------------------------------------------------------------
# EXECUTOR SETUP (STATEFUL)
# ------------------------------------------------------------

test_dir = File.expand_path("test_files", __dir__)

tools = {
  "read_file" => lambda do |path:|
    full_path = File.expand_path(path, test_dir)
    return { error: "Path must be within test_files directory" } unless full_path.start_with?(test_dir)

    return { error: "File not found: #{path}" } unless File.exist?(full_path)

    {
      path: path,
      content: File.read(full_path),
      size: File.size(full_path)
    }
  end,

  "read_reference" => lambda do |reference_name:|
    # Read external reference files
    reference_files = {
      "style_guide" => "ruby_style_guide.txt",
      "checklist" => "code_review_checklist.txt"
    }

    filename = reference_files[reference_name.to_s]
    unless filename
      return { error: "Unknown reference: #{reference_name}. Available: #{reference_files.keys.join(", ")}" }
    end

    full_path = File.expand_path(filename, test_dir)
    return { error: "Reference file not found: #{filename}" } unless File.exist?(full_path)

    {
      reference_name: reference_name,
      content: File.read(full_path),
      size: File.size(full_path)
    }
  end
}

executor_client = client_for(
  model: ENV.fetch("OLLAMA_MODEL", "llama3.1:8b"),
  temperature: 0.2,
  timeout: 60
)

executor = Ollama::Agent::Executor.new(
  executor_client,
  tools: tools
)

def step_limit_reached?(step, max_steps)
  return false if step <= max_steps

  puts "\n⚠️  Maximum steps reached (#{max_steps})"
  true
end

def build_status(context, step)
  {
    file_read: context[:file_read] ? "YES" : "NO",
    references_read: context[:references_read].empty? ? "NONE" : context[:references_read].join(", "),
    has_analysis: context[:analysis] ? "YES" : "NO",
    step_number: step
  }
end

def missing_references(references_read)
  %w[style_guide checklist] - references_read
end

def early_plan_for(context)
  return { "action" => "finish", "reason" => "Analysis complete" } if context[:analysis]

  if context[:file_read] && context[:references_read].length >= 2
    return { "action" => "analyze_with_reference",
             "reason" => "File and all references read, ready to analyze" }
  end

  return nil unless context[:file_read]

  missing_refs = missing_references(context[:references_read])
  return nil if missing_refs.empty?

  { "action" => "read_reference",
    "reason" => "File read, need to read missing references: #{missing_refs.join(", ")}" }
end

def planner_prompt(status)
  <<~PROMPT
    You are a planning agent for code analysis with external reference data.

    Available actions:
    - read_file: Read the target code file (ONLY if file_read is NO)
    - read_reference: Read external reference data (style_guide or checklist) - ONLY if not already read
    - analyze_with_reference: Analyze code using the reference data (ONLY if file_read is YES and BOTH references are read)
    - finish: Complete task (ONLY if analysis exists)

    Current Status:
    #{status.to_json}

    CRITICAL RULES (follow strictly in order):
    1. If file_read is NO → use read_file (DO NOT read file if already read)
    2. If file_read is YES and references_read is missing style_guide or checklist → use read_reference for the missing one
    3. If file_read is YES and BOTH references are read and analysis is NO → use analyze_with_reference
    4. If analysis exists → use finish

    DO NOT:
    - Read file if file_read is YES
    - Read a reference if it's already in references_read
    - Analyze if analysis already exists
    - Finish if analysis does not exist

    Decide the next action. Return ONLY valid JSON.
  PROMPT
end

def plan_next_action(planner, decision_schema, status, context)
  early_plan = early_plan_for(context)
  return early_plan if early_plan

  planner.run(prompt: planner_prompt(status), schema: decision_schema)
end

def handle_plan(plan, context, executor, test_dir)
  case plan["action"]
  when "read_file"
    handle_read_file(context, test_dir)
  when "read_reference"
    handle_read_reference(context, test_dir)
  when "analyze_with_reference"
    handle_analyze_with_reference(context, executor, test_dir)
  when "finish"
    handle_finish
  else
    raise "Unknown action: #{plan["action"]}"
  end
end

def handle_read_file(context, test_dir)
  if context[:file_read]
    puts "\n⚠️  File already read, skipping..."
    return :skip
  end

  puts "\n→ Executor: reading target file"

  full_path = File.expand_path(context[:target_file], test_dir)
  if File.exist?(full_path)
    context[:file_content] = File.read(full_path)
    context[:file_read] = true
    puts "\n✅ File content read (#{context[:file_content].length} bytes)"
  else
    puts "\n❌ File not found: #{context[:target_file]}"
    context[:file_read] = false
  end

  :continue
end

def reference_file_name(reference_name)
  reference_name == "style_guide" ? "ruby_style_guide.txt" : "code_review_checklist.txt"
end

def handle_read_reference(context, test_dir)
  puts "\n→ Executor: reading reference data"

  references_to_read = missing_references(context[:references_read])
  if references_to_read.empty?
    puts "\n⚠️  All references already read"
    return :skip
  end

  reference_name = references_to_read.first
  puts "\nReading reference: #{reference_name}"

  ref_file = reference_file_name(reference_name)
  ref_path = File.expand_path(ref_file, test_dir)

  if File.exist?(ref_path)
    context[:reference_data][reference_name] = File.read(ref_path)
    context[:references_read] << reference_name
    puts "\n✅ Reference '#{reference_name}' loaded (#{context[:reference_data][reference_name].length} bytes)"
  else
    puts "\n❌ Reference file not found: #{ref_file}"
  end

  :continue
end

def analysis_system_prompt
  <<~PROMPT
    You are a Ruby code analysis agent. Analyze code using the provided reference guidelines and checklists.
    Compare the code against the reference standards and provide specific recommendations.
  PROMPT
end

def analysis_user_prompt(code, reference_context)
  <<~PROMPT
    Analyze this Ruby code using the reference data:

    CODE TO ANALYZE:
    #{code}

    REFERENCE DATA:
    #{reference_context}

    Provide a detailed analysis that:
    1. Compares the code against the style guide
    2. Checks items from the code review checklist
    3. Provides specific, actionable recommendations
    4. References specific guidelines from the reference data

    Keep your analysis focused and reference the external data when making recommendations.
  PROMPT
end

def handle_analyze_with_reference(context, executor, test_dir)
  if context[:analysis]
    puts "\n⚠️  Analysis already complete, skipping..."
    return :skip
  end

  unless context[:file_read]
    puts "\n❌ Cannot analyze: file not read yet"
    return :skip
  end

  if context[:references_read].length < 2
    puts "\n❌ Cannot analyze: need both references (have: #{context[:references_read].join(", ")})"
    return :skip
  end

  puts "\n→ Executor: analyzing code using reference data"

  reference_context = context[:reference_data].map do |name, content|
    "#{name.upcase}:\n#{content}\n"
  end.join("\n---\n\n")

  result = executor.run(
    system: analysis_system_prompt,
    user: analysis_user_prompt(context[:file_content], reference_context)
  )

  puts "\nExecutor result:"
  puts result
  puts "\n#{"=" * 60}"

  context[:analysis] = result
  :continue
end

def handle_finish
  puts "\n→ Agent finished"
  :finish
end

# ------------------------------------------------------------
# AGENT LOOP
# ------------------------------------------------------------

context = {
  target_file: "user_creator.rb",
  file_read: false,
  file_content: nil,
  references_read: [],
  reference_data: {},
  analysis: nil
}

step = 0
max_steps = 15

loop do
  step += 1
  puts "\n→ Planner step #{step}"

  break if step_limit_reached?(step, max_steps)

  status = build_status(context, step)
  plan = plan_next_action(planner, decision_schema, status, context)
  pp plan

  result = handle_plan(plan, context, executor, test_dir)
  break if result == :finish
  next if result == :skip
end

# ------------------------------------------------------------
# FINAL ASSERTIONS
# ------------------------------------------------------------

puts "\n→ Assertions"

success = true

unless context[:file_read]
  puts "❌ No file read"
  success = false
end

unless context[:references_read].any?
  puts "❌ No references read"
  success = false
end

unless context[:analysis]
  puts "❌ No analysis performed"
  success = false
end

raise "❌ MULTI-STEP AGENT WITH EXTERNAL DATA FAILED" unless success

puts "\n✅ MULTI-STEP AGENT WITH EXTERNAL DATA PASSED"
puts "\nReferences used: #{context[:references_read].join(", ")}"
puts "\nAnalysis length: #{context[:analysis].length} characters"
puts "\n=== END ===\n"

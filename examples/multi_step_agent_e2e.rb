#!/usr/bin/env ruby
# frozen_string_literal: true

# Load .env file if available (overload to ensure .env takes precedence over shell env)
begin
  require "dotenv"
  Dotenv.overload
rescue LoadError
  # dotenv not available, skip
end

# Use local code instead of installed gem
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "ollama_client"
require "json"
require "fileutils"

puts "\n=== MULTI-STEP AGENT E2E TEST ===\n"

# Configuration via environment variables (defaults for local testing)

def client_for(model:, temperature:, timeout:)
  config = Ollama::Config.new
  config.base_url = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
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
      "enum" => %w[read_file write_file list_files analyze_code finish]
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

  "write_file" => lambda do |path:, content:|
    full_path = File.expand_path(path, test_dir)
    return { error: "Path must be within test_files directory" } unless full_path.start_with?(test_dir)

    # Extract code from markdown code blocks if present
    code_content = content
    if content.include?("```")
      # Extract content between ```ruby and ``` or ``` and ```
      match = content.match(/```(?:ruby)?\n?(.*?)```/m)
      code_content = match[1].strip if match
    end

    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, code_content)

    {
      path: path,
      written: true,
      size: File.size(full_path)
    }
  end,

  "list_files" => lambda do |directory: "."|
    full_path = File.expand_path(directory, test_dir)
    return { error: "Directory must be within test_files directory" } unless full_path.start_with?(test_dir)

    return { error: "Directory not found: #{directory}" } unless Dir.exist?(full_path)

    files = Dir.glob(File.join(full_path, "*")).map do |file|
      {
        name: File.basename(file),
        type: File.directory?(file) ? "directory" : "file",
        size: File.directory?(file) ? nil : File.size(file)
      }
    end

    {
      directory: directory,
      files: files
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
    has_analysis: context[:file_analysis] || context[:analysis_complete] ? "YES" : "NO",
    write_attempted: context[:write_attempted] ? "YES" : "NO",
    step_number: step
  }
end

def planner_prompt(status, context)
  <<~PROMPT
    You are a planning agent for file operations.

    Available actions:
    - read_file: Read a file (ONLY if file_read is NO)
    - analyze_code: Analyze code (ONLY if file_read is YES and has_analysis is NO)
    - write_file: Write refactored code (OPTIONAL - use maximum once, then finish)
    - finish: Complete task (use when file_read is YES and has_analysis is YES - this is the preferred action after analysis)

    Current Status:
    #{status.to_json}

    Full Context:
    #{context.compact.to_json}

    CRITICAL RULES (follow strictly in order):
    1. If file_read is NO → use read_file
    2. If file_read is YES and has_analysis is NO → use analyze_code (ONLY ONCE, then move to rule 3)
    3. If has_analysis is YES → IMMEDIATELY use finish (the task is complete after analysis)
    4. DO NOT use write_file - analysis is the goal, not refactoring
    5. DO NOT use analyze_code if has_analysis is already YES
    6. The workflow is: read → analyze → finish (that's it, 3 steps maximum)

    Decide the next action. Return ONLY valid JSON.
  PROMPT
end

def plan_next_action(planner, decision_schema, status, context)
  planner.run(prompt: planner_prompt(status, context), schema: decision_schema)
end

def handle_plan(plan, context, executor, test_dir)
  case plan["action"]
  when "read_file"
    handle_read_file(context, test_dir)
  when "write_file"
    handle_write_file(context, executor, test_dir)
  when "list_files"
    handle_list_files(context, executor)
  when "analyze_code"
    handle_analyze_code(context, executor, test_dir)
  when "finish"
    handle_finish
  else
    raise "Unknown action: #{plan["action"]}"
  end
end

def handle_read_file(context, test_dir)
  puts "\n→ Executor: reading file"

  full_path = File.expand_path(context[:file_path], test_dir)
  if File.exist?(full_path)
    actual_content = File.read(full_path)
    context[:file_content] = actual_content
    context[:file_read] = true
    puts "\nFile content read (#{actual_content.length} bytes)"
  else
    puts "\n❌ File not found: #{context[:file_path]}"
    context[:file_read] = false
  end

  :continue
end

def write_system_prompt(file_path)
  <<~PROMPT
    You are a file writing agent. You MUST use the write_file tool to write files.
    Call the write_file tool with path='#{file_path}' and the refactored code as content.
    Provide clean, working Ruby code. Extract code from markdown if needed.
  PROMPT
end

def write_user_prompt(file_path, file_analysis)
  <<~PROMPT
    Write refactored Ruby code to #{file_path}.
    Use the write_file tool with path='#{file_path}' and provide the improved code based on: #{file_analysis}
  PROMPT
end

def handle_write_file(context, executor, test_dir)
  puts "\n→ Executor: writing file"

  if context[:file_written]
    puts "\n⚠️  File already written, skipping..."
    context[:write_attempted] = true
    return :skip
  end

  result = executor.run(
    system: write_system_prompt(context[:file_path]),
    user: write_user_prompt(context[:file_path], context[:file_analysis])
  )

  puts "\nExecutor result:"
  puts result

  full_path = File.expand_path(context[:file_path], test_dir)
  if File.exist?(full_path)
    context[:file_written] = true
    context[:write_attempted] = true
    puts "\n✅ File written successfully"
  else
    context[:write_attempted] = true
    puts "\n⚠️  File write may have failed (file not found)"
  end

  :continue
end

def handle_list_files(context, executor)
  puts "\n→ Executor: listing files"

  result = executor.run(
    system: "You are a file listing agent. Use the list_files tool to see available files.",
    user: "List all files in the test_files directory"
  )

  puts "\nExecutor result:"
  puts result

  context[:file_list] = result
  :continue
end

def analysis_system_prompt
  <<~PROMPT
    You are a Ruby code analysis agent. Analyze code for issues and improvements.
    Provide a concise analysis with specific recommendations.
    Return ONLY your analysis, no tool calls needed.
  PROMPT
end

def analysis_user_prompt(code_to_analyze)
  <<~PROMPT
    Analyze this Ruby code:

    #{code_to_analyze}

    Identify issues, suggest improvements, and recommend refactoring if needed.
    Keep your analysis concise and actionable (max 200 words).
  PROMPT
end

def handle_analyze_code(context, executor, test_dir)
  puts "\n→ Executor: analyzing code"

  if context[:file_analysis]
    puts "\n⚠️  Code already analyzed, skipping..."
    return :skip
  end

  code_to_analyze = context[:file_content]
  unless code_to_analyze
    full_path = File.expand_path(context[:file_path], test_dir)
    code_to_analyze = File.exist?(full_path) ? File.read(full_path) : "File not found"
  end

  result = executor.run(
    system: analysis_system_prompt,
    user: analysis_user_prompt(code_to_analyze)
  )

  puts "\nExecutor result:"
  puts result

  context[:file_analysis] = result
  context[:analysis_complete] = true
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
  file_path: "user_creator.rb",
  file_read: false,
  file_content: nil,
  file_analysis: nil,
  analysis_complete: false,
  file_written: false,
  write_attempted: false,
  files_created: []
}

step = 0
max_steps = 10

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

unless context[:file_analysis] || context[:analysis_complete]
  puts "❌ No code analysis performed"
  success = false
end

raise "❌ MULTI-STEP AGENT FAILED" unless success

puts "\n✅ MULTI-STEP AGENT PASSED"
puts "\nFiles created: #{context[:files_created].map { |f| f["path"] }.join(", ")}" if context[:files_created].any?
puts "\n=== END ===\n"

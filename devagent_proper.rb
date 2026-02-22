#!/usr/bin/env ruby
# frozen_string_literal: true

# DevAgent - Production Implementation using agent_runtime + ollama-client
# Following the ACTUAL gem APIs, not assumptions

require "English"
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "agent_runtime"
  gem "ollama-client"
  gem "json"
end

# ============================================================================
# TOOLS - Domain-specific Ruby callables (SRP: file operations only)
# ============================================================================

module DevTools
  def self.read_file(**args)
    path = args[:path] || args["path"]
    raise "Path required" unless path
    raise "Invalid path" if path.include?("..")
    raise "File not found: #{path}" unless File.exist?(path)

    {
      success: true,
      path: path,
      content: File.read(path),
      size: File.size(path)
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.write_file(**args)
    path = args[:path] || args["path"]
    content = args[:content] || args["content"]

    raise "Path and content required" unless path && content
    raise "Invalid path" if path.include?("..")
    raise "Unsafe path" if path.start_with?("/")

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)

    {
      success: true,
      path: path,
      bytes_written: content.bytesize,
      done: false # Not terminal, can continue
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.list_files(**args)
    directory = args[:directory] || args["directory"] || "."
    raise "Invalid path" if directory.include?("..")

    files = Dir.glob("#{directory}/**/*").reject { |f| File.directory?(f) }

    {
      success: true,
      directory: directory,
      files: files,
      count: files.count,
      done: false
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.validate_syntax(**args)
    path = args[:path] || args["path"]
    raise "File not found: #{path}" unless File.exist?(path)

    case File.extname(path)
    when ".rb"
      output = `ruby -c #{path} 2>&1`
      valid = $CHILD_STATUS.success?
      { success: true, valid: valid, language: "ruby", output: output }
    when ".js"
      output = `node --check #{path} 2>&1`
      valid = $CHILD_STATUS.success?
      { success: true, valid: valid, language: "javascript", output: output }
    else
      { success: true, valid: true, language: "unknown", skipped: true }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.finalize(**args)
    summary = args[:summary] || args["summary"] || "Task completed"

    {
      success: true,
      summary: summary,
      done: true # TERMINAL - signals completion
    }
  end
end

# ============================================================================
# AGENT - Using actual AgentRuntime::Agent API
# ============================================================================

class DevAgent
  attr_reader :agent, :state, :audit_log

  def initialize(model: "llama3.2")
    # 1. Setup Ollama client (pure transport)
    @client = Ollama::Client.new(model: model)

    # 2. Register tools (Ruby callables only)
    @tools = AgentRuntime::ToolRegistry.new({
                                              "read_file" => method(:tool_read_file),
                                              "write_file" => method(:tool_write_file),
                                              "list_files" => method(:tool_list_files),
                                              "validate_syntax" => method(:tool_validate_syntax),
                                              "finalize" => method(:tool_finalize)
                                            })

    # 3. Define decision schema (strict contract)
    @schema = {
      "type" => "object",
      "required" => %w[action params reasoning],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => %w[read_file write_file list_files validate_syntax finalize finish]
        },
        "params" => {
          "type" => "object",
          "additionalProperties" => true
        },
        "reasoning" => {
          "type" => "string"
        }
      }
    }

    # 4. Create Planner (LLM interface, no side effects)
    @planner = AgentRuntime::Planner.new(
      client: @client,
      schema: @schema,
      prompt_builder: method(:build_prompt)
    )

    # 5. Create Policy with convergence detection
    @policy = DevAgentPolicy.new

    # 6. Create Executor (tool execution only)
    @executor = AgentRuntime::Executor.new(tool_registry: @tools)

    # 7. Create State (explicit, serializable)
    @state = AgentRuntime::State.new

    # 8. Create AuditLog (optional but recommended)
    @audit_log = AgentRuntime::AuditLog.new

    # 9. Create Agent (decision loop coordinator)
    @agent = AgentRuntime::Agent.new(
      planner: @planner,
      policy: @policy,
      executor: @executor,
      state: @state,
      audit_log: @audit_log
    )
  end

  def execute(user_request)
    puts "\n🤖 DevAgent Starting..."
    puts "📝 Request: #{user_request}\n\n"

    # Run the agent loop (uses /generate for planning)
    result = @agent.run(initial_input: user_request)

    print_summary(result)
    result
  end

  def execute_step(user_request)
    puts "\n🤖 DevAgent Single Step..."
    puts "📝 Request: #{user_request}\n\n"

    # Single step execution
    result = @agent.step(input: user_request)

    print_summary(result)
    result
  end

  private

  # Tool wrappers that call domain logic
  def tool_read_file(**args)
    result = DevTools.read_file(**args)
    puts "  📖 Read: #{args[:path] || args["path"]}" if result[:success]
    result
  end

  def tool_write_file(**args)
    result = DevTools.write_file(**args)
    puts "  ✍️  Write: #{args[:path] || args["path"]}" if result[:success]
    result
  end

  def tool_list_files(**args)
    result = DevTools.list_files(**args)
    puts "  📂 List: #{result[:count]} files" if result[:success]
    result
  end

  def tool_validate_syntax(**args)
    result = DevTools.validate_syntax(**args)
    status = result[:valid] ? "✓" : "✗"
    puts "  #{status} Validate: #{args[:path] || args["path"]}" if result[:success]
    result
  end

  def tool_finalize(**args)
    result = DevTools.finalize(**args)
    puts "  🎯 Finalize: #{result[:summary]}"
    result
  end

  # Prompt builder (called by Planner)
  def build_prompt(input:, state:)
    context = state.data.empty? ? "No previous context" : state.to_json

    <<~PROMPT
      You are a precise software development agent.

      AVAILABLE TOOLS:
      - read_file(path: string)
      - write_file(path: string, content: string)
      - list_files(directory: string)
      - validate_syntax(path: string)
      - finalize(summary: string) - Call this when task is complete

      RULES:
      1. Work methodically, one step at a time
      2. Use tools to inspect before modifying
      3. Validate syntax after creating code files
      4. Call finalize when the task is complete
      5. Use finish action only if you cannot proceed

      USER REQUEST: #{input}

      CURRENT CONTEXT: #{context}

      OUTPUT FORMAT (JSON):
      {
        "action": "tool_name or finish",
        "params": { "param": "value" },
        "reasoning": "why this step"
      }

      Respond with JSON only.
    PROMPT
  end

  def print_summary(_result)
    puts "\n#{"=" * 70}"
    puts "EXECUTION COMPLETE"
    puts "=" * 70

    if @audit_log.logs.any?
      puts "\nActions taken:"
      @audit_log.logs.each_with_index do |log, i|
        action = log[:decision]&.dig("action") || "unknown"
        success = log[:result]&.dig(:success) ? "✓" : "✗"
        puts "  #{i + 1}. #{success} #{action}"
      end
    end

    puts "\nProgress signals: #{@state.progress.signals.inspect}" if @state.progress.signals.any?
    puts "=" * 70
  end
end

# ============================================================================
# POLICY - Convergence detection (domain-specific)
# ============================================================================

class DevAgentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when finalize has been called
    state.progress.include?(:finalize_called)
  end
end

# ============================================================================
# FSM VERSION - Using AgentFSM for formal state machine
# ============================================================================

class DevAgentFSM < AgentRuntime::AgentFSM
  def initialize(model: "llama3.2")
    @client = Ollama::Client.new(model: model)

    @tools = AgentRuntime::ToolRegistry.new({
                                              "read_file" => DevTools.method(:read_file),
                                              "write_file" => DevTools.method(:write_file),
                                              "list_files" => DevTools.method(:list_files),
                                              "validate_syntax" => DevTools.method(:validate_syntax),
                                              "finalize" => DevTools.method(:finalize)
                                            })

    @schema = {
      "type" => "object",
      "required" => %w[action params],
      "properties" => {
        "action" => { "type" => "string" },
        "params" => { "type" => "object" }
      }
    }

    planner = AgentRuntime::Planner.new(
      client: @client,
      schema: @schema,
      prompt_builder: lambda { |input:, state:|
        "Task: #{input}\nContext: #{state.to_json}\n\nDecide next action."
      }
    )

    super(
      planner: planner,
      policy: DevAgentPolicy.new,
      executor: AgentRuntime::Executor.new(tool_registry: @tools),
      state: AgentRuntime::State.new,
      tool_registry: @tools,
      audit_log: AgentRuntime::AuditLog.new
    )
  end

  # Override if you need Ollama tool definitions for chat mode
  def build_tools_for_chat
    # Return Ollama::Tool objects if needed
    # For now, empty array means no tool calling in chat
    []
  end
end

# ============================================================================
# CLI
# ============================================================================

if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts <<~USAGE
      DevAgent - Proper agent_runtime + ollama-client implementation

      Usage:
        ruby devagent_proper.rb "list files in current directory"
        ruby devagent_proper.rb "create a hello.rb file that prints hello world"
        ruby devagent_proper.rb --fsm "create test.rb"

      Modes:
        Default: Uses Agent#run (multi-step loop with /generate)
        --step: Uses Agent#step (single decision)
        --fsm: Uses AgentFSM (formal state machine with PLAN/EXECUTE/OBSERVE)

      Architecture (actual agent_runtime API):

        Application
          ↓
        Agent/AgentFSM (decision loop)
          ├→ Planner (LLM interface, no side effects)
          │   └→ Ollama::Client (pure transport)
          ├→ Policy (validation, convergence)
          ├→ Executor (tool execution only)
          ├→ State (explicit, serializable)
          └→ AuditLog (optional logging)

      Key Rules:
        - /generate for planning (Agent#run, AgentFSM PLAN state)
        - /chat for execution (AgentFSM EXECUTE state)
        - LLM never executes tools
        - Tools are Ruby callables
        - Convergence via Policy#converged?
        - Tool results injected as role: "tool"
    USAGE
    exit 0
  end

  mode = :run
  request = []

  ARGV.each do |arg|
    case arg
    when "--step"
      mode = :step
    when "--fsm"
      mode = :fsm
    else
      request << arg
    end
  end

  user_request = request.join(" ")

  if user_request.empty?
    puts "Error: No request provided"
    exit 1
  end

  begin
    case mode
    when :step
      agent = DevAgent.new
      agent.execute_step(user_request)
    when :fsm
      puts "🔄 Running with FSM workflow (PLAN → EXECUTE → OBSERVE)"
      agent = DevAgentFSM.new
      agent.run(initial_input: user_request)
      puts "\nFSM States: #{agent.state_history.map { |s| s[:state] }.join(" → ")}"
    else
      agent = DevAgent.new
      agent.execute(user_request)
    end
  rescue StandardError => e
    puts "\n❌ Error: #{e.message}"
    puts e.backtrace.first(5) if ENV["DEBUG"]
    exit 1
  end
end

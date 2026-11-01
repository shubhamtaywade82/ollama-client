# frozen_string_literal: true

require_relative "history_sanitizer"
require_relative "schema_validator"
require_relative "json_fragment_extractor"
require_relative "model_profile"

module Ollama
  # Stateful multi-turn conversation object.
  # Manages message history, sanitizes reasoning blocks across turns,
  # and supports block-based streaming and structured output repair.
  class Chat
    attr_reader :client, :model, :options, :tools, :format, :think,
                :keep_alive, :profile, :trace_store
    attr_accessor :messages

    # rubocop:disable Metrics/ParameterLists
    def initialize(client, model: nil, system: nil, history: nil, tools: nil,
                   format: nil, think: nil, keep_alive: nil, options: nil,
                   profile: :auto, trace_store: nil)
      # rubocop:enable Metrics/ParameterLists
      @client = client
      @model = model || client.config.model
      @tools = tools
      @format = format
      @think = think
      @keep_alive = keep_alive
      @options = options ? options.dup : {}
      @profile = profile
      @trace_store = trace_store
      @messages = []

      add_system_message(system) if system
      Array(history).each { |msg| add_message(msg) }
    end

    def ask(prompt, tools: nil, format: nil, &block)
      add_message(role: "user", content: prompt)

      effective_format = format || @format
      response = execute_turn_with_repair(tools: tools, format: effective_format, &block)

      record_assistant_response(response)
      response
    end

    def with_instructions(instructions, append: false)
      if append && (existing = find_system_message)
        existing[:content] = "#{existing[:content]}\n\n#{instructions}"
      else
        @messages.reject! { |m| (m[:role] || m["role"]).to_s == "system" }
        add_system_message(instructions)
      end
      self
    end

    def with_model(model_name)
      @model = model_name
      self
    end

    def with_temperature(temp)
      @options[:temperature] = temp
      self
    end

    def with_think(level)
      @think = level
      self
    end

    def with_keep_alive(duration)
      @keep_alive = duration
      self
    end

    def with_tool(tool)
      @tools ||= []
      @tools << (tool.respond_to?(:to_tool_hash) ? tool.to_tool_hash : tool)
      self
    end

    def with_tools(*tools)
      tools.flatten.each { |t| with_tool(t) }
      self
    end

    def with_format(fmt)
      @format = fmt
      self
    end
    alias with_schema with_format

    def add_message(msg)
      @messages << (msg.is_a?(Hash) ? msg : msg.to_h)
    end

    def reset!
      sys = find_system_message
      @messages.clear
      @messages << sys if sys
      self
    end

    private

    def add_system_message(text)
      @messages.unshift({ role: "system", content: text })
    end

    def find_system_message
      @messages.find { |m| (m[:role] || m["role"]).to_s == "system" }
    end

    def record_assistant_response(response)
      sanitizer = HistorySanitizer.for(resolve_profile, trace_store: @trace_store)
      sanitizer.add(response, messages: @messages)
      tool_calls = response.message&.tool_calls
      @messages.last[:tool_calls] = tool_calls.map(&:to_h) if tool_calls&.any?
    end

    def resolve_profile
      return @profile if @profile.is_a?(ModelProfile)
      return ModelProfile.for(@model) if @profile == :auto

      ModelProfile.for("generic")
    end

    def execute_turn_with_repair(tools:, format:, &block)
      attempts = 0
      max_attempts = @client.config.retries + 1

      loop do
        attempts += 1
        response = dispatch_chat_turn(tools: tools, format: format, &block)
        validate_chat_schema!(response.content, format) if format
        return response
      rescue SchemaViolationError, InvalidJSONError => e
        raise e if attempts >= max_attempts

        repair_turn(response&.content, e.message)
      end
    end

    def dispatch_chat_turn(tools:, format:, &block)
      hooks = {}
      hooks[:on_token] = ->(token) { block.call(token) } if block

      @client.chat(
        messages: @messages, model: @model, tools: tools || @tools,
        format: format, think: @think, keep_alive: @keep_alive,
        options: @options, profile: @profile, stream: block ? true : nil, hooks: hooks
      )
    end

    def repair_turn(raw_content, error_msg)
      @messages << { role: "assistant", content: raw_content.to_s }
      repair_msg = "CRITICAL FIX: Your last response was invalid or violated the schema. " \
                   "Error: #{error_msg}. Return ONLY valid JSON."
      @messages << { role: "user", content: repair_msg }
    end

    def validate_chat_schema!(content, schema)
      return unless content && schema

      json_str = JsonFragmentExtractor.call(content)
      parsed = JSON.parse(json_str)
      SchemaValidator.validate!(parsed, schema) if schema.is_a?(Hash)
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse JSON response: #{e.message}"
    end
  end
end

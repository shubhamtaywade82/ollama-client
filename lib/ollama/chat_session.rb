# frozen_string_literal: true

require_relative "streaming_observer"
require_relative "agent/messages"

module Ollama
  # Stateful chat session for human-facing interactions.
  #
  # Chat sessions maintain conversation history and support streaming
  # for presentation purposes. They are isolated from agent internals
  # to preserve deterministic behavior in schema-first workflows.
  #
  # Example:
  #   client = Ollama::Client.new(config: Ollama::Config.new.tap { |c| c.allow_chat = true })
  #   observer = Ollama::StreamingObserver.new do |event|
  #     print event.text if event.type == :token
  #   end
  #   chat = Ollama::ChatSession.new(client, system: "You are helpful", stream: observer)
  #   chat.say("Hello")
  #   chat.say("Explain Ruby blocks")
  class ChatSession
    attr_reader :messages

    def initialize(client, system: nil, stream: nil)
      @client = client
      @messages = []
      @stream = stream
      @messages << Agent::Messages.system(system) if system
    end

    # Send a user message and get assistant response.
    #
    # @param text [String] User message text
    # @param model [String, nil] Model override (uses client config if nil)
    # @param format [Hash, nil] Optional JSON schema for formatting (best-effort, not guaranteed)
    # @param tools [Tool, Array<Tool>, Array<Hash>, nil] Optional tool definitions
    # @param options [Hash] Additional options (temperature, top_p, etc.)
    # @return [String] Assistant response content
    def say(text, model: nil, format: nil, tools: nil, options: {})
      @messages << Agent::Messages.user(text)

      response = if @stream
                   stream_response(model: model, format: format, tools: tools, options: options)
                 else
                   non_stream_response(model: model, format: format, tools: tools, options: options)
                 end

      content = response["message"]&.dig("content") || ""
      tool_calls = response["message"]&.dig("tool_calls")

      @messages << Agent::Messages.assistant(content, tool_calls: tool_calls) if content || tool_calls

      content
    end

    # Clear conversation history (keeps system message if present).
    def clear
      system_msg = @messages.find { |m| m["role"] == "system" }
      @messages = system_msg ? [system_msg] : []
    end

    private

    def stream_response(model:, format:, tools:, options:)
      @client.chat_raw(
        messages: @messages,
        model: model,
        format: format,
        tools: tools,
        options: options,
        allow_chat: true,
        stream: true
      ) do |chunk|
        delta = chunk.dig("message", "content")
        @stream.emit(:token, text: delta.to_s) if delta && !delta.to_s.empty?

        calls = chunk.dig("message", "tool_calls")
        if calls.is_a?(Array)
          calls.each do |call|
            name = call.dig("function", "name") || call["name"]
            @stream.emit(:tool_call_detected, name: name, data: call) if name
          end
        end

        # Emit final event when stream completes
        @stream.emit(:final) if chunk["done"] == true
      end
    end

    def non_stream_response(model:, format:, tools:, options:)
      @client.chat_raw(
        messages: @messages,
        model: model,
        format: format,
        tools: tools,
        options: options,
        allow_chat: true
      )
    end
  end
end

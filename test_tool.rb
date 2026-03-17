# frozen_string_literal: true

require_relative "lib/ollama_client"
require "pp"
client = Ollama::Client.new(config: Ollama::Config.new { |c| c.model = "qwen2.5-coder:7b" })
messages = [{ role: "user", content: "What is the weather in Paris?" }]
tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get weather",
      parameters: { type: "object", properties: { city: { type: "string" } } }
    }
  },
  {
    type: "function",
    function: {
      name: "get_time",
      description: "Get time",
      parameters: { type: "object", properties: {} }
    }
  }
]
response = client.chat(messages: messages, tools: tools)
pp response.instance_variable_get(:@data)

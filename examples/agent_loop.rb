# frozen_string_literal: true

require_relative "../lib/ollama_client"

# This is a very simple example of an "Agentic Loop" using ollama-client.
# A true agent requires:
# 1. State (Memory) -> The `messages` array
# 2. Tools (Actions) -> The `tools` array
# 3. A loop (Reason -> Act -> Observe)

client = Ollama::Client.new(
  config: Ollama::Config.new.tap do |c|
    # Note: Tool calling requires a capable model (like qwen2.5-coder or llama3.1)
    c.model = "llama3.1:8b"
  end
)

# 1. Provide the tools our agent can use
tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get the current weather for a city",
      parameters: {
        type: "object",
        properties: {
          city: { type: "string", description: "The name of the city, e.g. London" }
        },
        required: ["city"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "get_time",
      description: "Get the current time for a city",
      parameters: {
        type: "object",
        properties: {
          city: { type: "string", description: "The name of the city, e.g. London" }
        },
        required: ["city"]
      }
    }
  }
]

# Provide actual Ruby implementations of these tools
def get_weather(city:)
  # Simulate weather API
  case city.downcase
  when "paris" then "Sunny, 22°C"
  when "london" then "Rainy, 14°C"
  else "Cloudy, 18°C"
  end
end

def get_time(city:)
  # Simulate timezone math
  offset = case city.downcase
           when "paris" then 1   # CET (+1)
           when "london" then 0  # GMT
           when "tokyo" then 9   # JST (+9)
           else 0
           end

  (Time.now.utc + (offset * 3600)).strftime("%I:%M %p")
end

# 2. State (Memory)
messages = [
  { role: "system", content: "You are a helpful AI assistant. You must use tools to answer questions if you don't know the answer." },
  { role: "user", content: "What is the weather like in Paris right now? Also, what time is it?" }
]

puts "\n🤖 User: #{messages.last[:content]}"

# 3. The Agentic Loop
loop do
  response = client.chat(messages: messages, tools: tools)
  message = response.message

  # Append model's response to memory
  messages << message.to_h

  # Check if model wants to call any tools
  tool_calls = message.tool_calls || []

  if tool_calls.empty?
    # No tools to call, the model gave a final answer. We're done!
    puts "\n🎉 Agent Final Answer:\n#{message.content}"
    break
  end

  # The model requested to use tools. We execute them locally and feed results back.
  tool_calls.each do |tool_call|
    func_name = tool_call.name
    args = tool_call.arguments || {}

    puts "\n🔧 Agent decided to call tool: `#{func_name}` with args: #{args}"

    # Execute the Ruby function
    result = case func_name
             when "get_weather" then get_weather(city: args["city"])
             when "get_time" then get_time(city: args["city"])
             else "Error: Unknown tool"
             end

    puts "   -> Result: #{result}"

    # Append the observation (tool result) to memory using `role: tool`
    messages << {
      role: "tool",
      content: result.to_s
    }
  end

  # The loop continues. The model will see the tool results and decide what to do next.
end

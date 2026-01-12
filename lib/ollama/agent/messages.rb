# frozen_string_literal: true

module Ollama
  module Agent
    # Small helpers for building chat message hashes.
    module Messages
      def self.system(content)
        { role: "system", content: content.to_s }
      end

      def self.user(content)
        { role: "user", content: content.to_s }
      end

      def self.assistant(content, tool_calls: nil)
        msg = { role: "assistant", content: content.to_s }
        msg[:tool_calls] = tool_calls if tool_calls
        msg
      end

      # Tool results are sent back as role: "tool".
      # Some APIs require `tool_call_id` to associate results with calls.
      def self.tool(content:, name: nil, tool_call_id: nil)
        msg = { role: "tool", content: content.to_s }
        msg[:name] = name if name
        msg[:tool_call_id] = tool_call_id if tool_call_id
        msg
      end
    end
  end
end


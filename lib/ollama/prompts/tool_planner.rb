# frozen_string_literal: true

module Ollama
  module Prompts
    def self.tool_planner(tools:, rules: [])
      tool_lines = tools.map do |t|
        name = t[:name] || t["name"]
        description = t[:description] || t["description"]
        "- #{name}: #{description}"
      end.join("\n")

      rules_text = rules.map { |r| "- #{r}" }.join("\n")

      <<~PROMPT
        You are a planner.

        Available tools:
        #{tool_lines}

        Rules:
        #{rules_text}
        - Call ONLY one tool at a time
        - If no more actions are needed, return action = "finish"
        - Respond ONLY in JSON

        JSON format:
        {
          "action": "tool_name | finish",
          "input": { }
        }
      PROMPT
    end
  end
end


# frozen_string_literal: true

module Ollama
  module PromptAdapters
    # Gemma 4 prompt adapter.
    #
    # Gemma 4 activates thinking by prepending <|think|> to the system prompt
    # content rather than via a think: true API flag. This adapter injects
    # that tag automatically when think: true is requested.
    #
    # Multimodal ordering: image/audio parts are expected before text, which
    # is handled by MultimodalInput before messages are built.
    class Gemma4 < Base
      THINK_TAG = "<|think|>"
      TOOL_INSTRUCTION = "\n\nYou have access to tools. If a tool can help answer the user question, " \
                         "call it using the provided function schema."

      # Inject <|think|> into the system message when think is enabled.
      # Also inject tool usage instructions if tools are present.
      def adapt_messages(messages, think: false, tools: nil)
        system_idx = messages.index { |m| role_of(m) == "system" }

        if system_idx
          messages = messages.dup
          msg = messages[system_idx].dup
          content = content_of(msg)

          # Add thinking tag if requested
          content = "#{THINK_TAG}#{content}" if think && !content.start_with?(THINK_TAG)

          # Add tool instruction if tools present
          content = "#{content}#{TOOL_INSTRUCTION}" if tools&.any? && !content.include?(TOOL_INSTRUCTION)

          set_content(msg, content)
          messages[system_idx] = msg
        elsif think || tools&.any?
          # Create a system message if none exists but we need to inject tags/instructions
          content = +""
          content << THINK_TAG if think
          content << TOOL_INSTRUCTION if tools&.any?
          messages = [{ role: "system", content: content }] + messages
        end

        messages
      end

      # Gemma 4 uses the system-prompt tag — do NOT send think: true to API.
      def inject_think_flag?
        false
      end

      private

      def role_of(msg)
        (msg[:role] || msg["role"]).to_s
      end

      def content_of(msg)
        (msg[:content] || msg["content"]).to_s
      end

      def set_content(msg, value)
        if msg.key?(:content)
          msg[:content] = value
        else
          msg["content"] = value
        end
      end
    end
  end
end

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

      # Inject <|think|> into the system message when think is enabled.
      # If there is no system message, a bare system message is prepended.
      def adapt_messages(messages, think: false)
        return messages unless think

        idx = messages.index { |m| role_of(m) == "system" }
        if idx
          msg = messages[idx]
          content = content_of(msg)
          return messages if content.start_with?(THINK_TAG)

          updated = msg.dup
          set_content(updated, "#{THINK_TAG}#{content}")
          messages = messages.dup
          messages[idx] = updated
        else
          system_msg = { role: "system", content: THINK_TAG }
          messages = [system_msg] + messages
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

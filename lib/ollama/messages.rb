# frozen_string_literal: true

module Ollama
  # Build the array-of-hash messages shape accepted by `Client.chat(messages:)`.
  #
  # Example:
  #
  #   messages = Ollama::Messages.new
  #     .system("You are a senior Ruby engineer.")
  #     .user("Review this code.", attachment: Ollama::Attachment.file("lib.rb"))
  #     .image("What is in this screenshot?", file: "ui.png")
  #
  #   client.chat(messages: messages.to_h)
  class Messages
    # @param base [Array<Hash>, nil] starting messages to copy into this builder
    def initialize(base = nil)
      @messages = Array(base).dup
    end

    # Add/replace the system message. When +content+ is nil, removes any existing
    # system message.
    def system(content)
      if content.nil?
        @messages.reject! { |m| role_for(m) == "system" }
      else
        replace_or_append("system", content)
      end
      self
    end

    def role_for(message)
      message.is_a?(Hash) ? (message[:role] || message["role"]).to_s : nil
    end

    # Replace the first message with +role+ if present; otherwise append.
    def replace_or_append(role, content)
      existing = @messages.index { |m| role_for(m) == role }
      message = { role: role, content: content.to_s }
      if existing
        @messages[existing] = message
      else
        @messages << message
      end
      self
    end

    # Append a message of the given role.
    def append(role, content)
      @messages << { role: role, content: content.to_s }
      self
    end

    # Add an assistant message.
    def assistant(content)
      append("assistant", content)
    end

    # Add a user message, optionally with an attachment.
    def user(content, attachment: nil)
      message = { role: "user", content: content.to_s }
      if attachment
        attachments = Array(attachment).map { |a| a.is_a?(Attachment) ? a.to_h : a }
        message[:images] = attachments if attachments.any?
      end
      @messages << message
      self
    end

    # Add an image-only user message. +attachment+ may be an Attachment or a
    # path/IO/base64-string. Accepts +text+ as optional user content.
    def image(text = nil, attachment:)
      message = { role: "user", content: text ? text.to_s : "" }
      attachments = Array(attachment).map { |a| a.is_a?(Attachment) ? a.to_h : a }
      message[:images] = attachments
      @messages << message
      self
    end

    # Append an already-formed Ollama message hash or any object responding to
    # `to_h`.
    def add(message)
      normalized = message.is_a?(Hash) ? message.dup : message.to_h
      normalized = { role: "user", content: normalized.to_s } unless normalized.key?(:role) || normalized.key?("role")
      @messages << normalized
      self
    end

    # Return the plain messages array accepted by `chat(messages:)`.
    def to_h
      @messages.dup.freeze
    end

    # Return number of messages stored.
    def size
      @messages.size
    end

    # Enumerate messages without exposing the backing array.
    def each(&block)
      to_h.each(&block)
    end

    def inspect
      "#<#{self.class.name} size=#{@messages.size}>"
    end
  end
end

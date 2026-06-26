# frozen_string_literal: true

module Ollama
  # Typed attachment payload for multimodal inputs.
  #
  # Each variant normalizes to a single hash accepted by Ollama as the
  # +:images+ entry on a user message: +{ type: "...", data: "..." }+.
  #
  # Example:
  #
  #   Ollama::Attachment.file("photo.png")
  #   # => { type: "file", data: "photo.png" }
  #
  #   Ollama::Attachment.base64(b64_string)
  #   # => { type: "base64", data: b64_string }
  #
  #   Ollama::Attachment.url("https://...")
  #   # => { type: "url", data: "https://..." }
  class Attachment
    attr_reader :type, :data

    # @param type [String, Symbol] one of +file+, +base64+, +url+
    # @param data [String, #read]
    def initialize(type, data)
      @type = type.to_s
      @data = coerce(data)
    end

    # +type:+ +"file"+, +data:+ +path+ (string or +Pathname+). Reads as base64 when a file path is supplied.
    # Uses base64-encoded file when a file path is supplied.
    def self.file(path)
      path = path.to_s
      data = if path.include?("\n") || path.include?("+")
               path
             else
               base64_from_file(path)
             end
      new("file", data)
    end

    # +type:+ +"base64"+, +data:+ +base64-encoded string+
    def self.base64(data)
      new("base64", data)
    end

    # +type:+ +"url"+, +data:+ +remote URL+
    def self.url(url)
      new("url", url.to_s)
    end

    def to_h
      { "type" => type, "data" => data }
    end

    private

    def coerce(value)
      return value if value.is_a?(String)
      return value.read if value.respond_to?(:read)

      value.to_s
    end

    class << self
      private

      def base64_from_file(path)
        File.file?(path) && File.exist?(path) ? [File.binread(path)].pack("m") : path
      rescue SystemCallError
        path
      end
    end
  end
end

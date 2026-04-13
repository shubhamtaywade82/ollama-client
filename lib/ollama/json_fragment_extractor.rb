# frozen_string_literal: true

require_relative "errors"

module Ollama
  # Pulls a single balanced JSON object or array out of a string that may contain
  # surrounding prose (used when models wrap JSON in explanations).
  class JsonFragmentExtractor
    def self.call(text)
      new(text).extract
    end

    def initialize(text)
      @text = text
    end

    def extract
      validate_present!
      stripped = @text.lstrip
      return try_parse_entire_document(stripped) if json_document_prefix?(stripped)

      extract_balanced_fragment
    end

    private

    def validate_present!
      raise InvalidJSONError, "Empty response body" if @text.nil? || @text.empty?
    end

    def json_document_prefix?(stripped)
      stripped.start_with?("{", "[", "\"", "-", "t", "f", "n") || stripped.match?(/\A\d/)
    end

    def try_parse_entire_document(stripped)
      JSON.parse(stripped)
      stripped
    rescue JSON::ParserError
      extract_balanced_fragment
    end

    def extract_balanced_fragment
      start_idx = @text.index(/[{\[]/)
      raise InvalidJSONError, "No JSON found in response. Response: #{@text[0..200]}..." unless start_idx

      scan_balanced_json(start_idx)
    end

    def scan_balanced_json(start_idx)
      stack = []
      in_string = false
      escape = false
      i = start_idx

      while i < @text.length
        byte = @text.getbyte(i)

        if in_string
          in_string, escape = advance_string_state(byte, in_string, escape)
        else
          case byte
          when 34 then in_string = true # double-quote
          when 123 then stack << 125 # { -> }
          when 91 then stack << 93 # [ -> ]
          when 125, 93 # }, ]
            expected = stack.pop
            raise InvalidJSONError, "Malformed JSON. Response: #{@text[start_idx, 200]}..." if expected != byte

            return @text[start_idx..i] if stack.empty?
          end
        end

        i += 1
      end

      raise InvalidJSONError, "Incomplete JSON in response. Response: #{@text[start_idx, 200]}..."
    end

    def advance_string_state(byte, in_string, escape)
      return [in_string, false] if escape

      case byte
      when 92 then [in_string, true] # backslash
      when 34 then [false, false] # double-quote
      else [in_string, false]
      end
    end
  end
end

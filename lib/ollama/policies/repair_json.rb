# frozen_string_literal: true

require_relative "base"
require "json"

module Ollama
  module Policies
    # RepairJson policy - attempts to repair malformed JSON responses
    class RepairJson < Base
      attr_reader :max_repairs, :strategies, :hooks

      # @param max_repairs [Integer] Maximum number of repair attempts (default: 2)
      # @param strategies [Array<Symbol>] Repair strategies to try in order (default: [:balanced, :extract_object])
      # @param hooks [Hash] Optional hooks: :before_repair, :after_repair
      def initialize(max_repairs: 2, strategies: %i[balanced extract_object], hooks: {})
        super()
        @max_repairs = max_repairs
        @strategies = strategies
        @hooks = hooks
      end

      def call(request, env = {})
        response = @app.call(request, env)

        # Only attempt repair on non-streaming responses with JSON parsing errors
        return response unless response&.body
        return response if env[:stream_chunk]

        attempt_repair(response, env)
      rescue JSON::ParserError => e
        @hooks[:on_repair_error]&.call(e, env)
        raise
      end

      def stream(request, env = {}, &block)
        @app.stream(request, env, &block)
      end

      private

      def attempt_repair(response, env)
        return response if response.body.nil? || response.body.empty?

        begin
          JSON.parse(response.body)
          response # Already valid JSON
        rescue JSON::ParserError => e
          @hooks[:before_repair]&.call(response.body, env)

          repaired_body = nil
          @strategies.each do |strategy|
            repaired_body = send("repair_#{strategy}", response.body, e)
            break if repaired_body
          end

          raise e unless repaired_body

          @hooks[:after_repair]&.call(repaired_body, env)
          # Return new response with repaired body
          response.class.new(
            status: response.status,
            headers: response.headers,
            body: repaired_body,
            raw: response.raw,
            duration_ms: response.duration_ms
          )
        end
      end

      # Repair using balanced brace/bracket matching
      def repair_balanced(body, _error)
        return nil unless body.is_a?(String)

        open_braces = 0
        open_brackets = 0
        in_string = false
        escape = false

        body.each_char do |char|
          if escape
            escape = false
            next
          end

          if char == "\\" && in_string
            escape = true
            next
          end

          if char == '"'
            in_string = !in_string
            next
          end

          next if in_string

          case char
          when "{" then open_braces += 1
          when "}" then open_braces -= 1
          when "[" then open_brackets += 1
          when "]" then open_brackets -= 1
          end
        end

        # Add missing closing braces/brackets
        result = body.dup
        result += "}" * open_braces if open_braces.positive?
        result += "]" * open_brackets if open_brackets.positive?

        begin
          JSON.parse(result)
          result
        rescue JSON::ParserError
          nil
        end
      end

      # Extract first valid JSON object/array from text
      def repair_extract_object(body, _error)
        return nil unless body.is_a?(String)

        # Find first { or [
        start_idx = body.index(/[{\[]/)
        return nil unless start_idx

        # Try to extract from start_idx
        (start_idx..(body.length - 1)).each do |end_idx|
          candidate = body[start_idx..end_idx]
          begin
            JSON.parse(candidate)
            return candidate
          rescue JSON::ParserError
            next
          end
        end

        nil
      end
    end
  end
end

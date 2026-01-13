# frozen_string_literal: true

require "json"

module Ollama
  # Response wrapper for chat_raw() that provides method access to response data
  #
  # Example:
  #   response = client.chat_raw(...)
  #   response.message&.tool_calls  # Access tool_calls
  #   response.message&.content     # Access content
  class Response
    def initialize(data)
      @data = data
    end

    # Access the message object
    def message
      msg = @data["message"] || @data[:message]
      return nil unless msg

      Message.new(msg)
    end

    # Access raw data as hash
    def to_h
      @data
    end

    # Delegate other methods to underlying hash
    def method_missing(method, *, &)
      if @data.respond_to?(method)
        @data.public_send(method, *, &)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @data.respond_to?(method, include_private) || super
    end

    # Message wrapper for accessing message fields
    class Message
      def initialize(data)
        @data = data
      end

      def content
        @data["content"] || @data[:content]
      end

      def tool_calls
        calls = @data["tool_calls"] || @data[:tool_calls]
        return [] unless calls

        calls.map { |call| ToolCall.new(call) }
      end

      def role
        @data["role"] || @data[:role]
      end

      def to_h
        @data
      end

      # ToolCall wrapper for accessing tool call fields
      class ToolCall
        def initialize(data)
          @data = data
        end

        def id
          @data["id"] || @data[:id] || @data["tool_call_id"] || @data[:tool_call_id]
        end

        def function
          func = @data["function"] || @data[:function]
          return nil unless func

          Function.new(func)
        end

        def name
          function&.name
        end

        def arguments
          function&.arguments
        end

        def to_h
          @data
        end

        # Function wrapper for accessing function fields
        class Function
          def initialize(data)
            @data = data
          end

          def name
            @data["name"] || @data[:name]
          end

          def arguments
            args = @data["arguments"] || @data[:arguments]
            return {} unless args

            args.is_a?(String) ? JSON.parse(args) : args
          rescue JSON::ParserError
            {}
          end

          def to_h
            @data
          end
        end
      end
    end
  end
end

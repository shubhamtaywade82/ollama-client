# frozen_string_literal: true

require "json"

module Ollama
  # Response wrapper for chat() that provides method access to response data
  #
  # Example:
  #   response = client.chat(messages: [...])
  #   response.message&.content      # Access content
  #   response.message&.thinking     # Access thinking output
  #   response.message&.tool_calls   # Access tool_calls
  #   response.done?                 # Check if generation finished
  #   response.done_reason           # Why generation stopped
  #   response.total_duration        # Total time in nanoseconds
  class Response
    def initialize(data)
      @data = data || {}
    end

    # Access the message object
    def message
      msg = @data["message"] || @data[:message]
      return nil unless msg

      Message.new(msg)
    end

    # Whether generation has finished
    def done?
      @data["done"] || @data[:done] || false
    end

    # Reason the generation stopped
    def done_reason
      @data["done_reason"] || @data[:done_reason]
    end

    # Model name used
    def model
      @data["model"] || @data[:model]
    end

    # ISO 8601 timestamp of response creation
    def created_at
      @data["created_at"] || @data[:created_at]
    end

    # Total time spent generating in nanoseconds
    def total_duration
      @data["total_duration"] || @data[:total_duration]
    end

    # Time spent loading the model in nanoseconds
    def load_duration
      @data["load_duration"] || @data[:load_duration]
    end

    # Number of tokens in the prompt
    def prompt_eval_count
      @data["prompt_eval_count"] || @data[:prompt_eval_count]
    end

    # Time spent evaluating the prompt in nanoseconds
    def prompt_eval_duration
      @data["prompt_eval_duration"] || @data[:prompt_eval_duration]
    end

    # Number of tokens generated in the response
    def eval_count
      @data["eval_count"] || @data[:eval_count]
    end

    # Time spent generating tokens in nanoseconds
    def eval_duration
      @data["eval_duration"] || @data[:eval_duration]
    end

    # Log probability information when logprobs are enabled
    def logprobs
      @data["logprobs"] || @data[:logprobs]
    end

    # Access raw data as hash
    def to_h
      @data
    end

    # Convenient content accessor (shorthand for message&.content)
    def content
      message&.content
    end

    # Delegate hash access to underlying data
    def [](key)
      @data[key]
    end

    # Delegate other methods to underlying hash
    def method_missing(method, ...)
      return super unless @data.respond_to?(method)

      @data.public_send(method, ...)
    end

    def respond_to_missing?(method, include_private = false)
      @data.respond_to?(method, include_private) || super
    end

    # Message wrapper for accessing message fields
    class Message
      def initialize(data)
        @data = data || {}
      end

      def content
        @data["content"] || @data[:content]
      end

      def thinking
        @data["thinking"] || @data[:thinking]
      end

      def tool_calls
        calls = @data["tool_calls"] || @data[:tool_calls]
        return [] unless calls

        calls.map { |call| ToolCall.new(call) }
      end

      def role
        @data["role"] || @data[:role]
      end

      def images
        @data["images"] || @data[:images]
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

          def description
            @data["description"] || @data[:description]
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

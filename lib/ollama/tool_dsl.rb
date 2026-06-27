# frozen_string_literal: true

module Ollama
  # Optional class-based DSL for tools.
  #
  # Subclasses produce a tool hash compatible with `tools:`.
  #
  # Example:
  #
  #  class WeatherTool < Ollama::ToolDSL
  #    description "Get current weather for a city"
  #    tool_name "get_weather"
  #    input do
  #      string :city, description: "The name of the city"
  #      string :unit, optional: true, default: "celsius"
  #    end
  #    call { constructor }
  #  end
  #
  #  client.chat(messages: [...], tools: [WeatherTool.to_tool_hash])
  class ToolDSL
    class << self
      attr_reader :tool_description, :input_schema, :output_schema, :user_block

      def description(text)
        @tool_description = text
      end

      def tool_name(text = nil)
        @tool_name = text unless text.nil?
        @tool_name
      end

      def input(&block)
        @input_schema = SchemaDSL.define(&block).to_h
      end

      def output(&block)
        @output_schema = SchemaDSL.define(&block).to_h
      end

      def call(&block)
        @user_block = block
        def_constructor
      end

      def to_tool_hash
        function = {
          "name" => tool_name || tool_method_name,
          "description" => tool_description || "",
          "strict" => true
        }
        function["parameters"] = input_schema if input_schema

        {
          "type" => "function",
          "function" => function
        }
      end

      private

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@tool_description, nil)
        subclass.instance_variable_set(:@tool_name, nil)
        subclass.instance_variable_set(:@input_schema, nil)
        subclass.instance_variable_set(:@output_schema, nil)
        subclass.instance_variable_set(:@user_block, nil)
        subclass.singleton_class.remove_method(:constructor) if subclass.singleton_class.method_defined?(:constructor)
      end

      def def_constructor
        return if respond_to?(:constructor)

        singleton_class.define_method(:constructor) do
          @constructor ||= instance_exec(&user_block)
        end
      end

      def tool_method_name
        if tool_name && !tool_name.to_s.strip.empty?
          tool_name.to_s.strip
        else
          base = tool_description.to_s.strip
          base = base.gsub(/[^0-9a-zA-Z]+/, "_").downcase.strip
          base = base.sub(/\A_/, "").sub(/_\z/, "")
          base.empty? ? "unnamed_tool" : base
        end
      end
    end
  end
end

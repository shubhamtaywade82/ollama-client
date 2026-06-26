# frozen_string_literal: true

module Ollama
  # Base DSL for reusable, testable prompt templates that produce
  # `Ollama::Messages`.
  #
  # Inputs are declared with keyword names. The blocks/methods below can
  # reference those names and call `client.chat(messages: instance.messages)`.
  #
  # Example:
  #
  #   class ExplainCode < Ollama::Prompt
  #     input :code, :language
  #
  #     system <<~PROMPT
  #       You are a senior Ruby engineer.
  #     PROMPT
  #
  #     user do
  #       code
  #       "Please review the #{language} implementation."
  #     end
  #   end
  #
  #   prompt = ExplainCode.new("def foo; end", "ruby").messages
  #   client.chat(messages: prompt.to_h)
  class Prompt
    # @param values [Array, Hash] input values in declaration order, or a hash
    #   of keyword values.
    def initialize(*values)
      @input_values = if values.size == 1 && values.first.is_a?(Hash) && !self.class.inputs.empty?
                        values.first
                      else
                        values
                      end
      @messages = Messages.new
    end

    class << self
      attr_reader :inputs, :system_content

      def input(*names)
        @inputs = names.freeze
      end

      def system(text)
        @system_content = text
      end

      private

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@inputs, nil)
        subclass.instance_variable_set(:@system_content, nil)
      end
    end

    # Return the built message list.
    def messages
      @messages.system(self.class.system_content) if self.class.system_content
      user_block = self.class.user_block
      instance_eval(&user_block) if user_block
      @messages
    end

    # Return the built message list, alias for `messages`.
    def to_h
      messages.to_h
    end

    # Forward equality to `to_h`.
    def ==(other)
      other.is_a?(Prompt) && to_h == other.to_h
    end

    class << self
      attr_reader :user_block

      def user(&block)
        @user_block = block
      end
    end
  end
end

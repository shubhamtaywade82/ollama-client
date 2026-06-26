# frozen_string_literal: true

module Ollama
  # Reusable prompt templates that produce `Ollama::Messages`.
  #
  # Example DSL:
  #
  #   class ExplainCode < Ollama::Prompt
  #     input(:code, :language)
  #     system "You are a senior Ruby engineer."
  #     user { [code, "Please review the #{language} implementation."].compact.join("\n") }
  #   end
  #
  #   ExplainCode.new("def foo; end", "ruby").to_h
  class Prompt
    class << self
      attr_reader :inputs, :system_content, :user_block

      def input(*names)
        @inputs = names.freeze
      end

      def system(text)
        @system_content = text
      end

      def user(&block)
        @user_block = block
      end

      private

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@inputs, nil)
        subclass.instance_variable_set(:@system_content, nil)
        subclass.instance_variable_set(:@user_block, nil)
      end
    end

    def initialize(*values)
      @input_values = resolve_input_values(*values)
      @messages = Messages.new
      build!
    end

    def messages
      @messages
    end

    def to_h
      messages.to_h
    end

    def ==(other)
      other.is_a?(Prompt) && to_h == other.to_h
    end

    private

    def resolve_input_values(*values)
      if values.size == 1 && values.first.is_a?(Hash) && self.class.inputs.present?
        values.first
      elsif values.size == self.class.inputs&.size
        self.class.inputs.zip(values).to_h
      else
        values.first
      end
    end

    def build!
      @messages.system(self.class.system_content) if self.class.system_content
      return unless self.class.user_block

      input_values = Array(@input_values).compact
      content = instance_exec(*input_values, &self.class.user_block)
      @messages.user(content.to_s) if content
    end
  end
end

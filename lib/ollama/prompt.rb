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

    attr_reader :messages

    def to_h
      messages.to_h
    end

    def ==(other)
      other.is_a?(Prompt) && to_h == other.to_h
    end

    private

    def resolve_input_values(*values)
      first = values.first
      hash_like = first.respond_to?(:[]) && first.respond_to?(:keys)
      inputs = self.class.inputs

      if values.size == 1 && (first.is_a?(Hash) || hash_like) && inputs&.any?
        first
      elsif values.size == inputs&.size
        inputs.zip(values).to_h
      end
    end

    def build!
      @messages.system(self.class.system_content) if self.class.system_content
      return unless self.class.user_block

      input_values = if @input_values.is_a?(Hash) || (!@input_values.is_a?(Array) && @input_values.respond_to?(:keys))
                       Array(self.class.inputs).compact.map { |key| @input_values[key] }
                     else
                       Array(@input_values).compact
                     end

      Array(instance_exec(*input_values, &self.class.user_block)).each do |content|
        @messages.user(content.to_s) if content
      end
    end
  end
end

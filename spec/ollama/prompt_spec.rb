# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Prompt do
  describe ".new" do
    context "with hash input" do
      it "maps hash keys to instance inputs" do
        values = Object.new
        allow(values).to receive(:[]).with(:code).and_return("def hi; end")
        allow(values).to receive(:[]).with(:language).and_return("ruby")
        allow(values).to receive(:keys).and_return(%i[code language])

        klass = Class.new(described_class) do
          input :code, :language
          system "system"
          user { |code, language| [code, "Language: #{language}"].compact.join(" ") }
        end

        instance = klass.new(values)
        msgs = instance.messages.to_h
        user = msgs.find { |m| m["role"] == "user" }
        expect(user["content"]).to include("def hi; end")
        expect(user["content"]).to include("ruby")
      end
    end

    context "with positional values" do
      it "stores values in declaration order" do
        klass = Class.new(described_class) do
          input :code, :language
          system "system"
          user { |code, language| [code, language].compact.join(" ") }
        end

        instance = klass.new("code", "ruby")
        msgs = instance.messages.to_h
        user = msgs.find { |m| m["role"] == "user" }
        expect(user["content"]).to include("code")
        expect(user["content"]).to include("ruby")
      end
    end
  end

  describe "#messages" do
    it "includes the system message when declared" do
      instance = build_prompt_instance
      msgs = instance.messages.to_h
      expect(msgs.first["role"]).to eq("system")
    end

    it "returns the same Messages object on repeated calls" do
      instance = build_prompt_instance
      first = instance.messages
      second = instance.messages
      expect(first).to be(second)
    end
  end

  describe "#to_h" do
    it "delegates to messages.to_h" do
      instance = build_prompt_instance
      expect(instance.to_h).to eq(instance.messages.to_h)
    end
  end

  describe "#==" do
    it "compares by messages.to_h" do
      a = build_prompt_instance
      b = build_prompt_instance
      expect(a).to eq(b)
    end
  end

  describe "inheritance" do
    it "resets state between instances" do
      klass = Class.new(described_class) do
        input :code, :language
        system "system"
        user { |code, language| [code, language].compact.join(" ") }
      end

      a = klass.new("code1", "rb")
      b = klass.new("code2", "py")
      expect(a.messages.to_h.last["content"]).to include("code1")
      expect(b.messages.to_h.last["content"]).to include("code2")
    end
  end

  def build_prompt_instance
    klass = Class.new(described_class) do
      input :code, :language
      system "system"
      user { |code, language| [code, language].compact.join(" ") }
    end

    klass.new("def foo; end", "ruby")
  end
end

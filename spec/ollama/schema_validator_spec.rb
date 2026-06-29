# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::SchemaValidator do
  describe ".validate!" do
    it "validates data against schema" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => "test" }
      expect { described_class.validate!(data, schema) }.not_to raise_error
    end

    it "raises SchemaViolationError on invalid data" do
      schema = {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
      data = { "name" => 123 }
      expect do
        described_class.validate!(data, schema)
      end.to raise_error(Ollama::SchemaViolationError)
    end
  end
end

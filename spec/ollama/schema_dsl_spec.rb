# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::SchemaDSL do
  describe ".define" do
    it "builds object schemas with required fields" do
      schema = described_class.define do
        string :name, description: "User name"
        number :confidence, minimum: 0, maximum: 1
      end.to_h

      expect(schema["type"]).to eq("object")
      expect(schema["required"]).to match_array(%w[name confidence])
      expect(schema["properties"]["name"]["type"]).to eq("string")
      expect(schema["properties"]["confidence"]["type"]).to eq("number")
    end

    it "omits required when all fields are optional" do
      schema = described_class.define do
        string :search, optional: true
      end.to_h

      expect(schema).not_to have_key("required")
    end

    it "generates enums" do
      schema = described_class.define do
        string :status, enum: %w[pending paid failed]
      end.to_h

      expect(schema["properties"]["status"]["enum"]).to eq(%w[pending paid failed])
    end

    it "sets numeric bounds" do
      schema = described_class.define do
        number :confidence, minimum: 0, maximum: 1
      end.to_h

      expect(schema["properties"]["confidence"]).to include(
        "type" => "number",
        "minimum" => 0,
        "maximum" => 1
      )
    end

    it "supports array and object fields" do
      schema = described_class.define do
        array :items, items: { "type" => "string" }
        object :meta, properties: { "key" => { "type" => "string" } }
      end.to_h

      expect(schema["properties"]["items"]["type"]).to eq("array")
      expect(schema["properties"]["meta"]["type"]).to eq("object")
    end
  end
end

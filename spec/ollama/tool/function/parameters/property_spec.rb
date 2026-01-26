# frozen_string_literal: true

require "json"

RSpec.describe Ollama::Tool::Function::Parameters::Property do
  describe "#initialize" do
    it "creates property with type and description" do
      property = described_class.new(
        type: "string",
        description: "Location name"
      )

      expect(property.type).to eq("string")
      expect(property.description).to eq("Location name")
      expect(property.enum).to be_nil
    end

    it "converts type and description to strings" do
      property = described_class.new(
        type: :string,
        description: :description
      )

      expect(property.type).to eq("string")
      expect(property.description).to eq("description")
    end

    it "accepts enum array" do
      property = described_class.new(
        type: "string",
        description: "Unit",
        enum: %w[celsius fahrenheit]
      )

      expect(property.enum).to eq(%w[celsius fahrenheit])
    end

    it "converts enum to array of strings" do
      property = described_class.new(
        type: "string",
        description: "Unit",
        enum: [:celsius, "fahrenheit"]
      )

      expect(property.enum).to eq(%w[celsius fahrenheit])
    end

    it "handles nil enum" do
      property = described_class.new(
        type: "string",
        description: "Location",
        enum: nil
      )

      expect(property.enum).to be_nil
    end
  end

  describe ".from_hash" do
    it "creates property from hash" do
      hash = {
        type: "string",
        description: "Location",
        enum: %w[paris london]
      }

      property = described_class.from_hash(hash)

      expect(property.type).to eq("string")
      expect(property.description).to eq("Location")
      expect(property.enum).to eq(%w[paris london])
    end

    it "handles string keys" do
      hash = {
        "type" => "string",
        "description" => "Location"
      }

      property = described_class.from_hash(hash)

      expect(property.type).to eq("string")
    end

    it "handles missing enum" do
      hash = {
        type: "string",
        description: "Location"
      }

      property = described_class.from_hash(hash)

      expect(property.enum).to be_nil
    end
  end

  describe "#to_h" do
    it "converts property to hash" do
      property = described_class.new(
        type: "string",
        description: "Location"
      )

      hash = property.to_h

      expect(hash["type"]).to eq("string")
      expect(hash["description"]).to eq("Location")
    end

    it "includes enum in hash when present" do
      property = described_class.new(
        type: "string",
        description: "Unit",
        enum: %w[celsius fahrenheit]
      )

      hash = property.to_h

      expect(hash["enum"]).to eq(%w[celsius fahrenheit])
    end

    it "omits enum when nil or empty" do
      property1 = described_class.new(
        type: "string",
        description: "Location",
        enum: nil
      )
      property2 = described_class.new(
        type: "string",
        description: "Location",
        enum: []
      )

      expect(property1.to_h).not_to have_key("enum")
      expect(property2.to_h).not_to have_key("enum")
    end
  end

  describe "#to_json" do
    it "serializes property to JSON" do
      property = described_class.new(
        type: "string",
        description: "Location"
      )

      json = property.to_json
      parsed = JSON.parse(json)

      expect(parsed["type"]).to eq("string")
      expect(parsed["description"]).to eq("Location")
    end
  end
end

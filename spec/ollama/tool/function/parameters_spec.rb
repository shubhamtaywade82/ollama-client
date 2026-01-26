# frozen_string_literal: true

require "json"

RSpec.describe Ollama::Tool::Function::Parameters do
  describe "#initialize" do
    it "creates parameters with type" do
      params = described_class.new(type: "object")

      expect(params.type).to eq("object")
      expect(params.properties).to eq({})
      expect(params.required).to eq([])
    end

    it "converts type to string" do
      params = described_class.new(type: :object)

      expect(params.type).to eq("object")
    end

    it "accepts properties hash" do
      property = Ollama::Tool::Function::Parameters::Property.new(
        type: "string",
        description: "Location"
      )
      params = described_class.new(
        type: "object",
        properties: { location: property }
      )

      expect(params.properties[:location]).to eq(property)
    end

    it "converts property hashes to Property objects" do
      params = described_class.new(
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "Location"
          }
        }
      )

      expect(params.properties[:location]).to be_a(Ollama::Tool::Function::Parameters::Property)
      expect(params.properties[:location].type).to eq("string")
    end

    it "accepts required array" do
      params = described_class.new(
        type: "object",
        required: %w[location city]
      )

      expect(params.required).to eq(%w[location city])
    end

    it "converts required to array of strings" do
      params = described_class.new(
        type: "object",
        required: [:location, "city"]
      )

      expect(params.required).to eq(%w[location city])
    end

    it "raises error for invalid property type" do
      expect do
        described_class.new(
          type: "object",
          properties: { location: "invalid" }
        )
      end.to raise_error(Ollama::Error, /Invalid property type/)
    end
  end

  describe ".from_hash" do
    it "creates parameters from hash" do
      hash = {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "Location"
          }
        },
        required: %w[location]
      }

      params = described_class.from_hash(hash)

      expect(params.type).to eq("object")
      expect(params.properties[:location]).to be_a(Ollama::Tool::Function::Parameters::Property)
      expect(params.required).to eq(%w[location])
    end

    it "handles string keys" do
      hash = {
        "type" => "object",
        "properties" => {},
        "required" => []
      }

      params = described_class.from_hash(hash)

      expect(params.type).to eq("object")
    end

    it "handles missing properties and required" do
      hash = { type: "object" }

      params = described_class.from_hash(hash)

      expect(params.properties).to eq({})
      expect(params.required).to eq([])
    end
  end

  describe "#to_h" do
    it "converts parameters to hash" do
      property = Ollama::Tool::Function::Parameters::Property.new(
        type: "string",
        description: "Location"
      )
      params = described_class.new(
        type: "object",
        properties: { location: property },
        required: %w[location]
      )

      hash = params.to_h

      expect(hash["type"]).to eq("object")
      expect(hash["properties"]).to be_a(Hash)
      expect(hash["required"]).to eq(%w[location])
    end

    it "omits empty properties and required" do
      params = described_class.new(type: "object")

      hash = params.to_h

      expect(hash).not_to have_key("properties")
      expect(hash).not_to have_key("required")
    end
  end

  # NOTE: empty? method is not implemented in Parameters class
  # This test documents expected behavior if the method is added
  describe "#empty? (not implemented)" do
    it "would return true when no properties or required" do
      params = described_class.new(type: "object")

      # Check manually if empty
      is_empty = params.properties.empty? && params.required.empty?
      expect(is_empty).to be true
    end

    it "would return false when properties exist" do
      property = Ollama::Tool::Function::Parameters::Property.new(
        type: "string",
        description: "Location"
      )
      params = described_class.new(
        type: "object",
        properties: { location: property }
      )

      is_empty = params.properties.empty? && params.required.empty?
      expect(is_empty).to be false
    end

    it "would return false when required exists" do
      params = described_class.new(
        type: "object",
        required: %w[location]
      )

      is_empty = params.properties.empty? && params.required.empty?
      expect(is_empty).to be false
    end
  end
end

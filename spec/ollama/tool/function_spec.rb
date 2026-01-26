# frozen_string_literal: true

require "json"

RSpec.describe Ollama::Tool::Function do
  describe "#initialize" do
    it "creates function with name and description" do
      function = described_class.new(
        name: "get_weather",
        description: "Get weather for location"
      )

      expect(function.name).to eq("get_weather")
      expect(function.description).to eq("Get weather for location")
    end

    it "converts name and description to strings" do
      function = described_class.new(
        name: :get_weather,
        description: :description
      )

      expect(function.name).to eq("get_weather")
      expect(function.description).to eq("description")
    end

    it "creates default parameters if not provided" do
      function = described_class.new(
        name: "test",
        description: "Test"
      )

      expect(function.parameters).to be_a(Ollama::Tool::Function::Parameters)
      expect(function.parameters.type).to eq("object")
    end

    it "accepts custom parameters" do
      params = Ollama::Tool::Function::Parameters.new(
        type: "object",
        properties: {
          location: Ollama::Tool::Function::Parameters::Property.new(
            type: "string",
            description: "Location"
          )
        },
        required: %w[location]
      )

      function = described_class.new(
        name: "test",
        description: "Test",
        parameters: params
      )

      expect(function.parameters).to eq(params)
    end
  end

  describe ".from_hash" do
    it "creates function from hash" do
      hash = {
        name: "get_weather",
        description: "Get weather",
        parameters: {
          type: "object",
          properties: {}
        }
      }

      function = described_class.from_hash(hash)

      expect(function.name).to eq("get_weather")
      expect(function.description).to eq("Get weather")
      expect(function.parameters).to be_a(Ollama::Tool::Function::Parameters)
    end

    it "handles string keys" do
      hash = {
        "name" => "test",
        "description" => "Test"
      }

      function = described_class.from_hash(hash)

      expect(function.name).to eq("test")
    end

    it "handles missing parameters" do
      hash = {
        name: "test",
        description: "Test"
      }

      function = described_class.from_hash(hash)

      expect(function.parameters).to be_a(Ollama::Tool::Function::Parameters)
    end
  end

  describe "#to_h" do
    it "converts function to hash" do
      function = described_class.new(
        name: "test",
        description: "Test"
      )

      hash = function.to_h

      expect(hash[:name]).to eq("test")
      expect(hash[:description]).to eq("Test")
      expect(hash[:parameters]).to be_a(Hash)
    end

    it "includes parameters in hash" do
      params = Ollama::Tool::Function::Parameters.new(
        type: "object",
        properties: {}
      )
      function = described_class.new(
        name: "test",
        description: "Test",
        parameters: params
      )

      hash = function.to_h

      expect(hash[:parameters]).to be_a(Hash)
      expect(hash[:parameters]["type"]).to eq("object")
    end
  end

  describe "#to_json" do
    it "serializes function to JSON" do
      function = described_class.new(
        name: "test",
        description: "Test"
      )

      json = function.to_json
      parsed = JSON.parse(json)

      expect(parsed["name"]).to eq("test")
      expect(parsed["description"]).to eq("Test")
    end
  end
end

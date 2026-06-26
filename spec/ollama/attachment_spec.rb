# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ollama::Attachment do
  describe ".base64" do
    it "wraps the provided string" do
      expect(described_class.base64("abc").to_h).to eq({ "type" => "base64", "data" => "abc" })
    end
  end

  describe ".url" do
    it "converts value to a string" do
      url = URI("https://example.com/image.png")
      expect(described_class.url(url).to_h).to eq({ "type" => "url", "data" => "https://example.com/image.png" })
    end
  end

  describe ".file" do
    it "returns a file attachment hash for a non-existent path" do
      attachment = described_class.file("/nonexistent/image.png")
      expect(attachment.to_h).to have_key("type")
      expect(attachment.to_h).to have_key("data")
    end
  end

  describe "#to_h" do
    it "stringifies the type" do
      expect(described_class.new(:base64, "abc").to_h).to eq({ "type" => "base64", "data" => "abc" })
    end

    it "coerces IO objects" do
      io = StringIO.new("data")
      expect(described_class.new("file", io).data).to eq("data")
    end
  end
end

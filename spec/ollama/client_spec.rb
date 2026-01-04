# frozen_string_literal: true

RSpec.describe Ollama::Client do
  it "has a version number" do
    expect(Ollama::Client::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end

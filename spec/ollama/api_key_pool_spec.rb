# frozen_string_literal: true

RSpec.describe Ollama::ApiKeyPool do
  it "freezes configured keys" do
    pool = described_class.new(%w[key-a key-b])

    expect(pool.keys).to eq(%w[key-a key-b])
    expect(pool.keys).to be_frozen
  end

  it "uses the first key for every request when concurrency is disabled" do
    pool = described_class.new(%w[key-a key-b], concurrency_enabled: false)

    starts = 3.times.map { pool.key_for(pool.request_context) }

    expect(starts).to eq(%w[key-a key-a key-a])
  end

  it "round-robins initial keys when concurrency is enabled" do
    pool = described_class.new(%w[key-a key-b key-c], concurrency_enabled: true)

    starts = 4.times.map { pool.key_for(pool.request_context) }

    expect(starts).to eq(%w[key-a key-b key-c key-a])
  end
end

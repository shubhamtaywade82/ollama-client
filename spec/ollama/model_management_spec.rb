# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Ollama::Client do
  let(:client) { described_class.new(config: Ollama::Config.new) }

  describe "Blob API" do
    let(:digest) { "sha256:fe93a34d0ec22998a31658d2dbc9d30a95e882461f" }

    it "#blob_exists? returns true when blob exists" do
      stub_request(:head, "http://localhost:11434/api/blobs/#{digest}")
        .to_return(status: 200)

      expect(client.blob_exists?(digest: digest)).to be true
    end

    it "#blob_exists? returns false when blob is missing" do
      stub_request(:head, "http://localhost:11434/api/blobs/#{digest}")
        .to_return(status: 404)

      expect(client.blob_exists?(digest: digest)).to be false
    end

    it "#create_blob uploads content" do
      stub_request(:post, "http://localhost:11434/api/blobs/#{digest}")
        .with(body: "blob content")
        .to_return(status: 201)

      expect(client.create_blob(digest: digest, content: "blob content")).to be true
    end
  end

  describe "#create_model enhancements" do
    it "supports creating with modelfile" do
      stub_request(:post, "http://localhost:11434/api/create")
        .with(body: hash_including(
          "model" => "my-custom-model",
          "modelfile" => "FROM llama3\nSYSTEM You are a pirate"
        ))
        .to_return(status: 200, body: { status: "success" }.to_json)

      result = client.create_model(model: "my-custom-model", modelfile: "FROM llama3\nSYSTEM You are a pirate")
      expect(result["status"]).to eq("success")
    end

    it "supports creating with path" do
      stub_request(:post, "http://localhost:11434/api/create")
        .with(body: hash_including(
          "model" => "my-path-model",
          "path" => "/path/to/Modelfile"
        ))
        .to_return(status: 200, body: { status: "success" }.to_json)

      result = client.create_model(model: "my-path-model", path: "/path/to/Modelfile")
      expect(result["status"]).to eq("success")
    end

    it "raises ArgumentError if no source (from, modelfile, path) is provided" do
      expect { client.create_model(model: "invalid") }.to raise_error(ArgumentError, /required/)
    end
  end

  describe "#pull enhancements" do
    it "supports insecure and stream parameters" do
      stub_request(:post, "http://localhost:11434/api/pull")
        .with(body: { model: "llama3", stream: false, insecure: true })
        .to_return(status: 200, body: { status: "success" }.to_json)

      result = client.pull("llama3", insecure: true)
      expect(result["status"]).to eq("success")
    end

    it "supports streaming pull" do
      stub_request(:post, "http://localhost:11434/api/pull")
        .with(body: { model: "llama3", stream: true })
        .to_return(status: 200, body: "{\"status\":\"pulling\"}\n{\"status\":\"success\"}")

      progress = []
      hooks = { on_progress: ->(s) { progress << s["status"] } }
      
      client.pull("llama3", stream: true, hooks: hooks)
      expect(progress).to eq(["pulling", "success"])
    end
  end

  describe "#generate enhancements" do
    it "supports conversational context" do
      context_array = [1, 2, 3]
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: hash_including("context" => context_array))
        .to_return(status: 200, body: { response: "Next answer", context: [4, 5, 6] }.to_json)

      result = client.generate(prompt: "Next question", context: context_array, return_meta: true)
      expect(result["data"]).to eq("Next answer")
      expect(result["context"]).to eq([4, 5, 6])
    end
  end

  describe "Model lifecycle convenience methods" do
    it "#load_model sends empty prompt with keep_alive" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: { model: "llama3", prompt: "", keep_alive: "10m", stream: false })
        .to_return(status: 200, body: { response: "" }.to_json)

      expect(client.load_model(model: "llama3", keep_alive: "10m")).to be true
    end

    it "#unload_model sends keep_alive: 0" do
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: { model: "llama3", prompt: "", keep_alive: 0, stream: false })
        .to_return(status: 200, body: { response: "" }.to_json)

      expect(client.unload_model(model: "llama3")).to be true
    end
  end

  describe "Expanded Options" do
    it "supports new options like min_p and repeat_last_n" do
      opts = Ollama::Options.new(min_p: 0.05, repeat_last_n: 64, low_vram: true)
      
      stub_request(:post, "http://localhost:11434/api/generate")
        .with(body: hash_including("options" => hash_including(
          "min_p" => 0.05,
          "repeat_last_n" => 64,
          "low_vram" => true
        )))
        .to_return(status: 200, body: { response: "ok" }.to_json)

      expect { client.generate(prompt: "test", options: opts) }.not_to raise_error
    end
  end
end

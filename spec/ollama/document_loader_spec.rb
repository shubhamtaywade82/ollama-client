# frozen_string_literal: true

require "webmock/rspec"
require "tmpdir"
require "fileutils"

RSpec.describe Ollama::DocumentLoader do
  let(:temp_dir) { Dir.mktmpdir }
  let(:loader) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "expands directory path" do
      loader = described_class.new(".")
      expect(loader.instance_variable_get(:@directory)).to eq(File.expand_path("."))
    end

    it "accepts custom extensions" do
      loader = described_class.new(temp_dir, extensions: %w[.txt .rb])
      expect(loader.instance_variable_get(:@extensions)).to eq(%w[.txt .rb])
    end
  end

  describe "#load_all" do
    it "raises error if directory does not exist" do
      expect do
        described_class.new("/nonexistent/dir").load_all
      end.to raise_error(Ollama::Error, /Directory not found/)
    end

    it "loads all supported files from directory" do
      File.write(File.join(temp_dir, "test.txt"), "Text content")
      File.write(File.join(temp_dir, "test.md"), "# Markdown content")
      File.write(File.join(temp_dir, "test.json"), '{"key": "value"}')
      File.write(File.join(temp_dir, "test.csv"), "col1,col2\nval1,val2")

      result = loader.load_all

      expect(result).to be_a(Hash)
      expect(result["test.txt"]).to eq("Text content")
      expect(result["test.md"]).to include("Markdown content")
      expect(result["test.json"]).to include("key")
      expect(result["test.csv"]).to include("col1")
    end

    it "ignores unsupported file types" do
      File.write(File.join(temp_dir, "test.txt"), "Content")
      File.write(File.join(temp_dir, "test.rb"), "ruby code")

      result = loader.load_all

      expect(result).to have_key("test.txt")
      expect(result).not_to have_key("test.rb")
    end

    it "loads files recursively when recursive: true" do
      subdir = File.join(temp_dir, "subdir")
      FileUtils.mkdir_p(subdir)
      File.write(File.join(temp_dir, "root.txt"), "Root content")
      File.write(File.join(subdir, "sub.txt"), "Sub content")

      result = loader.load_all(recursive: true)

      expect(result).to have_key("root.txt")
      expect(result).to have_key("sub.txt")
    end

    it "does not load files recursively by default" do
      subdir = File.join(temp_dir, "subdir")
      FileUtils.mkdir_p(subdir)
      File.write(File.join(temp_dir, "root.txt"), "Root content")
      File.write(File.join(subdir, "sub.txt"), "Sub content")

      result = loader.load_all(recursive: false)

      expect(result).to have_key("root.txt")
      expect(result).not_to have_key("sub.txt")
    end

    it "handles empty directories" do
      result = loader.load_all
      expect(result).to eq({})
    end
  end

  describe "#load_file" do
    it "loads text file content" do
      file_path = File.join(temp_dir, "test.txt")
      File.write(file_path, "File content")

      result = loader.load_file(file_path)

      expect(result).to eq("File content")
    end

    it "loads markdown file content" do
      file_path = File.join(temp_dir, "test.md")
      File.write(file_path, "# Header\n\nContent")

      result = loader.load_file(file_path)

      expect(result).to include("Header")
      expect(result).to include("Content")
    end

    it "loads JSON file as formatted string" do
      file_path = File.join(temp_dir, "test.json")
      File.write(file_path, '{"key":"value"}')

      result = loader.load_file(file_path)

      expect(result).to include("key")
      expect(result).to include("value")
    end

    it "loads CSV file as formatted string" do
      file_path = File.join(temp_dir, "test.csv")
      File.write(file_path, "col1,col2\nval1,val2")

      result = loader.load_file(file_path)

      expect(result).to include("col1")
      expect(result).to include("val1")
    end

    it "loads unsupported file types as plain text" do
      file_path = File.join(temp_dir, "test.rb")
      File.write(file_path, "ruby code")

      result = loader.load_file(file_path)

      # DocumentLoader loads any file as text if extension is not recognized
      expect(result).to eq("ruby code")
    end

    it "handles missing files gracefully" do
      result = loader.load_file(File.join(temp_dir, "nonexistent.txt"))
      expect(result).to be_nil
    end
  end

  describe "#to_context" do
    it "combines all loaded documents into a single string" do
      File.write(File.join(temp_dir, "doc1.txt"), "First document")
      File.write(File.join(temp_dir, "doc2.txt"), "Second document")
      loader.load_all

      result = loader.to_context

      expect(result).to include("First document")
      expect(result).to include("Second document")
    end

    it "returns empty string when no documents loaded" do
      expect(loader.to_context).to eq("")
    end
  end

  describe "#[]" do
    it "returns document content by filename" do
      File.write(File.join(temp_dir, "test.txt"), "Content")
      loader.load_all

      expect(loader["test.txt"]).to eq("Content")
    end

    it "returns nil for unloaded file" do
      expect(loader["nonexistent.txt"]).to be_nil
    end
  end

  describe "#files" do
    it "returns array of loaded filenames" do
      File.write(File.join(temp_dir, "doc1.txt"), "Content 1")
      File.write(File.join(temp_dir, "doc2.txt"), "Content 2")
      loader.load_all

      files = loader.files

      expect(files).to be_an(Array)
      expect(files).to include("doc1.txt", "doc2.txt")
    end

    it "returns empty array when no files loaded" do
      expect(loader.files).to eq([])
    end
  end

  describe "#select" do
    it "filters documents by pattern" do
      File.write(File.join(temp_dir, "ruby_guide.txt"), "Ruby content")
      File.write(File.join(temp_dir, "python_guide.txt"), "Python content")
      loader.load_all

      result = loader.select(/ruby/)

      expect(result).to be_a(Hash)
      expect(result).to have_key("ruby_guide.txt")
      expect(result).not_to have_key("python_guide.txt")
    end

    it "returns empty hash when no matches" do
      File.write(File.join(temp_dir, "test.txt"), "Content")
      loader.load_all

      result = loader.select(/nonexistent/)

      expect(result).to eq({})
    end
  end
end

# frozen_string_literal: true

require "csv"
require "json"

module Ollama
  # Document loader for RAG (Retrieval-Augmented Generation)
  #
  # Loads files from a directory and provides them as context for LLM queries.
  # Supports: .txt, .md, .csv, .json files
  #
  # Example:
  #   loader = Ollama::DocumentLoader.new("docs/")
  #   context = loader.load_all
  #   result = client.generate(
  #     prompt: "Context: #{context}\n\nQuestion: What is Ruby?",
  #     schema: {...}
  #   )
  class DocumentLoader
    SUPPORTED_EXTENSIONS = %w[.txt .md .markdown .csv .json].freeze

    def initialize(directory, extensions: SUPPORTED_EXTENSIONS)
      @directory = File.expand_path(directory)
      @extensions = extensions
      @documents = {}
    end

    # Load all supported files from the directory
    #
    # @param recursive [Boolean] Load files from subdirectories
    # @return [Hash] Hash of filename => content
    def load_all(recursive: false)
      raise Error, "Directory not found: #{@directory}" unless Dir.exist?(@directory)

      pattern = recursive ? "**/*" : "*"
      files = Dir.glob(File.join(@directory, pattern)).select { |f| File.file?(f) }

      loaded_count = 0
      files.each do |file|
        next unless supported_file?(file)

        filename = File.basename(file)
        content = load_file(file)
        next if content.nil?

        @documents[filename] = content
        loaded_count += 1
      end

      @documents
    end

    # Load a specific file
    #
    # @param filename [String] Name of the file to load (can be relative or absolute)
    # @return [String] File content as text, or nil if file not found
    def load_file(filename)
      # Handle both relative and absolute paths
      full_path = if File.absolute_path?(filename)
                    filename
                  else
                    File.join(@directory, filename)
                  end

      return nil unless File.exist?(full_path)

      # Store with basename for consistency
      basename = File.basename(filename)

      ext = File.extname(filename).downcase
      content = File.read(full_path)

      parsed_content = case ext
                       when ".csv"
                         parse_csv(content)
                       when ".json"
                         parse_json(content)
                       else
                         # .txt, .md, .markdown, or any other text file
                         content
                       end

      # Store in documents hash
      @documents[basename] = parsed_content
      parsed_content
    end

    # Get all loaded documents as a single context string
    #
    # @param separator [String] Separator between documents
    # @return [String] Combined context from all documents
    def to_context(separator: "\n\n---\n\n")
      @documents.map do |filename, content|
        "File: #{filename}\n#{content}"
      end.join(separator)
    end

    # Get documents matching a pattern
    #
    # @param pattern [String, Regexp] Pattern to match filenames
    # @return [Hash] Matching documents
    def select(pattern)
      if pattern.is_a?(Regexp)
        @documents.select { |filename, _| filename.match?(pattern) }
      else
        @documents.select { |filename, _| filename.include?(pattern.to_s) }
      end
    end

    # Get a specific document by filename
    #
    # @param filename [String] Name of the document
    # @return [String, nil] Document content or nil if not found
    def [](filename)
      @documents[filename]
    end

    # List all loaded document names
    #
    # @return [Array<String>] Array of filenames
    def files
      @documents.keys
    end

    # Check if any documents are loaded
    #
    # @return [Boolean] True if documents are loaded
    def empty?
      @documents.empty?
    end

    private

    def supported_file?(file)
      ext = File.extname(file).downcase
      @extensions.include?(ext)
    end

    def parse_csv(content)
      rows = CSV.parse(content, headers: true)
      return content if rows.empty?

      # Convert CSV to readable text format
      headers = rows.headers || []
      text_rows = rows.map do |row|
        if headers.any?
          headers.map { |h| "#{h}: #{row[h]}" }.join(", ")
        else
          row.fields.join(", ")
        end
      end

      "CSV Data:\n" + text_rows.join("\n")
    end

    def parse_json(content)
      parsed = JSON.parse(content)
      JSON.pretty_generate(parsed)
    rescue JSON::ParserError
      content
    end
  end
end

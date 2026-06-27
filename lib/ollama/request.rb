# frozen_string_literal: true

require "uri"
require "json"

module Ollama
  # Immutable request object representing an API call.
  # Contains all information needed to execute a request without knowing about HTTP or JSON.
  class Request
    attr_reader :endpoint, :model, :messages, :prompt, :images, :tools, :schema, :options,
                :stream, :keep_alive, :think, :format, :metadata, :raw_options

    # Endpoint types: :chat, :generate, :embeddings, :show_model, :list_models, :version,
    #                 :create_model, :delete_model, :copy_model, :pull, :push, :list_running, :blob
    ENDPOINTS = %i[chat generate embeddings show_model list_models version
                   create_model delete_model copy_model pull push list_running blob].freeze

    # rubocop:disable Metrics/ParameterLists
    def initialize(endpoint:, model: nil, messages: nil, prompt: nil, images: nil,
                   tools: nil, schema: nil, options: nil, stream: nil, keep_alive: nil,
                   think: nil, format: nil, metadata: {}, raw_options: nil)
      @endpoint = endpoint.to_sym
      @model = model
      @messages = messages
      @prompt = prompt
      @images = images
      @tools = tools
      @schema = schema
      @options = options
      @stream = stream
      @keep_alive = keep_alive
      @think = think
      @format = format
      @metadata = metadata.freeze
      @raw_options = raw_options
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    # Build a request from endpoint-specific parameters
    def self.build(endpoint, **params)
      new(endpoint: endpoint, **params)
    end

    # Factory methods for common endpoints
    # rubocop:disable Metrics/ParameterLists
    def self.chat(model:, messages:, tools: nil, schema: nil, options: nil, stream: nil,
                  keep_alive: nil, think: nil, format: nil, **)
      new(endpoint: :chat, model: model, messages: messages, tools: tools, schema: schema,
          options: options, stream: stream, keep_alive: keep_alive, think: think, format: format)
    end

    def self.generate(model:, prompt:, schema: nil, options: nil, stream: nil, keep_alive: nil,
                      think: nil, images: nil, system: nil, suffix: nil, raw: nil, **)
      new(endpoint: :generate, model: model, prompt: prompt, schema: schema, options: options,
          stream: stream, keep_alive: keep_alive, think: think, images: images,
          raw_options: { system: system, suffix: suffix, raw: raw })
    end

    def self.embeddings(model:, input:, options: nil, keep_alive: nil, **)
      new(endpoint: :embeddings, model: model, prompt: input, options: options, keep_alive: keep_alive)
    end

    def self.show_model(model:, verbose: nil, **)
      new(endpoint: :show_model, model: model, raw_options: { verbose: verbose })
    end

    def self.list_models(**_)
      new(endpoint: :list_models)
    end

    def self.version(**_)
      new(endpoint: :version)
    end

    def self.create_model(model:, from: nil, modelfile: nil, path: nil, system: nil,
                          template: nil, license: nil, parameters: nil, messages: nil,
                          quantize: nil, stream: false, **)
      new(endpoint: :create_model, model: model,
          raw_options: { from: from, modelfile: modelfile, path: path, system: system,
                         template: template, license: license, parameters: parameters,
                         messages: messages, quantize: quantize, stream: stream })
    end

    def self.delete_model(model:, **_)
      new(endpoint: :delete_model, model: model)
    end

    def self.copy_model(source:, destination:, **_)
      new(endpoint: :copy_model, raw_options: { source: source, destination: destination })
    end

    def self.pull(model:, insecure: false, stream: false, **_)
      new(endpoint: :pull, model: model, raw_options: { insecure: insecure, stream: stream })
    end

    def self.push(model:, insecure: false, stream: false, **_)
      new(endpoint: :push, model: model, raw_options: { insecure: insecure, stream: stream })
    end

    def self.list_running(**_)
      new(endpoint: :list_running)
    end

    def self.blob(digest:, **_)
      new(endpoint: :blob, raw_options: { digest: digest })
    end
    # rubocop:enable Metrics/ParameterLists

    # Check if endpoint supports streaming
    def streaming?
      return @stream unless @stream.nil?

      %i[chat generate pull push create_model].include?(@endpoint)
    end

    # Get the base path for the endpoint
    def base_path
      case @endpoint
      when :chat then "/api/chat"
      when :generate then "/api/generate"
      when :embeddings then "/api/embeddings"
      when :show_model then "/api/show"
      when :list_models then "/api/tags"
      when :version then "/api/version"
      when :create_model then "/api/create"
      when :delete_model then "/api/delete"
      when :copy_model then "/api/copy"
      when :pull then "/api/pull"
      when :push then "/api/push"
      when :list_running then "/api/ps"
      when :blob then "/api/blobs"
      else "/api/#{@endpoint}"
      end
    end

    # Convert to a hash for serialization
    def to_h
      {
        endpoint: @endpoint,
        model: @model,
        messages: @messages,
        prompt: @prompt,
        images: @images,
        tools: @tools,
        schema: @schema,
        options: @options,
        stream: @stream,
        keep_alive: @keep_alive,
        think: @think,
        format: @format,
        metadata: @metadata,
        raw_options: @raw_options
      }.compact
    end

    # Equality based on all attributes
    def ==(other)
      return false unless other.is_a?(Request)

      to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end

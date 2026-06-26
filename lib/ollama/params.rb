# frozen_string_literal: true

module Ollama
  # Parameter objects for client methods to reduce parameter explosion
  module Params
    # Base parameter class with common behavior
    class Base
      def to_h
        instance_variables.each_with_object({}) do |var, hash|
          key = var.to_s.delete("@").to_sym
          value = instance_variable_get(var)
          hash[key] = value unless value.nil?
        end
      end

      def merge(other)
        other.to_h.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") && !v.nil? }
        self
      end
    end

    # Chat completion parameters
    class Chat < Base
      attr_accessor :messages, :model, :format, :tools, :stream, :think,
                    :keep_alive, :options, :logprobs, :top_logprobs, :hooks,
                    :profile, :inputs

      def initialize(messages:, model: nil, format: nil, tools: nil, stream: nil,
                     think: nil, keep_alive: nil, options: nil, logprobs: nil,
                     top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil)
        @messages = messages
        @model = model
        @format = format
        @tools = tools
        @stream = stream
        @think = think
        @keep_alive = keep_alive
        @options = options
        @logprobs = logprobs
        @top_logprobs = top_logprobs
        @hooks = hooks
        @profile = profile
        @inputs = inputs
      end
    end

    # Generate completion parameters
    class Generate < Base
      attr_accessor :prompt, :context, :schema, :model, :strict, :return_meta,
                    :system, :images, :think, :return_reasoning, :keep_alive,
                    :suffix, :raw, :options, :hooks

      def initialize(prompt:, context: nil, schema: nil, model: nil, strict: nil,
                     return_meta: false, system: nil, images: nil, think: nil,
                     return_reasoning: false, keep_alive: nil, suffix: nil,
                     raw: nil, options: nil, hooks: {})
        @prompt = prompt
        @context = context
        @schema = schema
        @model = model
        @strict = strict
        @return_meta = return_meta
        @system = system
        @images = images
        @think = think
        @return_reasoning = return_reasoning
        @keep_alive = keep_alive
        @suffix = suffix
        @raw = raw
        @options = options
        @hooks = hooks
      end
    end

    # Model creation parameters
    class CreateModel < Base
      attr_accessor :model, :from, :modelfile, :path, :system, :template,
                    :license, :parameters, :messages, :quantize, :stream

      def initialize(model:, from: nil, modelfile: nil, path: nil, system: nil,
                     template: nil, license: nil, parameters: nil, messages: nil,
                     quantize: nil, stream: false)
        @model = model
        @from = from
        @modelfile = modelfile
        @path = path
        @system = system
        @template = template
        @license = license
        @parameters = parameters
        @messages = messages
        @quantize = quantize
        @stream = stream
      end

      def self.from_kwargs(kwargs)
        new(**kwargs)
      end
    end

    # Embeddings parameters
    class Embeddings < Base
      attr_accessor :model, :input, :truncate, :dimensions, :keep_alive, :options

      def initialize(model:, input:, truncate: nil, dimensions: nil, keep_alive: nil, options: nil)
        @model = model
        @input = input
        @truncate = truncate
        @dimensions = dimensions
        @keep_alive = keep_alive
        @options = options
      end
    end

    # Pull/push model parameters
    class ModelTransfer < Base
      attr_accessor :model, :insecure, :stream, :hooks

      def initialize(model:, insecure: false, stream: false, hooks: {})
        @model = model
        @insecure = insecure
        @stream = stream
        @hooks = hooks
      end
    end
  end
end
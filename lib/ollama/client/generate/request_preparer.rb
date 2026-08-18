# frozen_string_literal: true

require_relative "../../request"

module Ollama
  class Client
    module Generate
      # Prepares Generate Request objects from client configuration and inputs
      class RequestPreparer
        def initialize(config:, provider:, schema_cache: {})
          @config = config
          @provider = provider
          @schema_cache = schema_cache
        end

        # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        def build_request(prompt:, context:, schema:, model:, hooks:, system: nil, images: nil,
                          think: nil, keep_alive: nil, suffix: nil, raw: nil, options: nil, client_instance: nil)
          config_model = @config.model
          config_timeout = @config.timeout
          base_url = @config.base_url

          stream_enabled = streaming_requested?(hooks)

          request_params = {
            model: model || config_model,
            prompt: prompt,
            stream: stream_enabled,
            options: client_instance.send(:build_options, options)
          }

          request_params[:context] = context if context
          request_params[:system] = system if system
          request_params[:images] = images if images
          request_params[:think] = think unless think.nil?
          request_params[:keep_alive] = keep_alive if keep_alive
          request_params[:suffix] = suffix if suffix
          request_params[:raw] = raw unless raw.nil?

          if schema
            request_params[:format] = schema
            request_params[:prompt] = enhance_prompt_for_json(prompt, schema)
          end

          Request.new(
            endpoint: :generate,
            model: model || config_model,
            prompt: request_params[:prompt],
            schema: schema,
            options: request_params[:options],
            stream: stream_enabled,
            keep_alive: keep_alive,
            think: think,
            format: request_params[:format],
            images: images,
            metadata: {
              base_url: base_url,
              timeout: config_timeout,
              hooks: hooks,
              uri: @provider.generate_endpoint
            },
            raw_options: {
              system: system,
              suffix: suffix,
              raw: raw,
              context: context
            }
          )
        end
        # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

        private

        def streaming_requested?(hooks)
          !(hooks[:on_token] || hooks[:on_error] || hooks[:on_complete]).nil?
        end

        def enhance_prompt_for_json(prompt, schema)
          return prompt if prompt.match?(/json|JSON/i)

          schema_summary = summarize_schema(schema)
          json_instruction = "CRITICAL: Respond with ONLY valid JSON (no markdown code blocks, no explanations). " \
                             "The JSON must include these exact required fields: #{schema_summary}"
          "#{prompt}\n\n#{json_instruction}"
        end

        def summarize_schema(schema)
          return "object" unless schema.is_a?(Hash)

          cache_key = schema.hash
          return @schema_cache[cache_key] if @schema_cache.key?(cache_key)

          required = schema["required"] || []
          properties = schema["properties"] || {}
          return "object" if required.empty? && properties.empty?

          example = {}
          required.each do |key|
            prop = properties[key] || {}
            example[key] = case prop["type"]
                           when "string" then "string_value"
                           when "number" then 0
                           when "boolean" then true
                           when "array" then []
                           else {}
                           end
          end

          required_list = required.map { |k| "\"#{k}\"" }.join(", ")
          example_json = JSON.pretty_generate(example)
          result = "Required fields: [#{required_list}]. Example structure:\n#{example_json}"
          @schema_cache[cache_key] = result
          result
        end
      end
    end
  end
end

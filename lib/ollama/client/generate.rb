# frozen_string_literal: true

require_relative "../generate_stream_handler"
require_relative "../json_fragment_extractor"
require_relative "../responses/generate"
require_relative "../serializers/generate"
require_relative "../parsers/generate"
require_relative "generate/response_formatter"

module Ollama
  class Client
    # Generate completion endpoint with auto-pull, retries, and structured output
    module Generate # rubocop:disable Metrics/ModuleLength
      # @param prompt [String] Text for the model to generate a response from (required)
      # @param context [Array<Integer>, nil] Context from a previous generate call for conversational memory
      # @param schema [Hash, nil] JSON Schema for structured output; also sets format
      # @param model [String, nil] Model name override
      # @param strict [Boolean] Enable strict JSON validation + repair retries
      # @param return_meta [Boolean] When true, wraps response with metadata
      # @param system [String, nil] System prompt
      # @param images [Array<String>, nil] Base64-encoded images for vision models
      # @param think [Boolean, String, nil] Enable thinking output (true/false/"high"/"medium"/"low")
      # @param return_reasoning [Boolean] Whether to extract and return reasoning structured separately
      # @param keep_alive [String, nil] Model keep-alive duration (e.g. "5m", "0")
      # @param suffix [String, nil] Fill-in-the-middle text after prompt
      # @param raw [Boolean, nil] When true, skip prompt templating
      # @param options [Hash, nil] Runtime options (temperature, top_p, num_ctx, etc.)
      # @param hooks [Hash] Streaming callbacks (:on_token, :on_error, :on_complete)
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/ParameterLists
      def generate(prompt:, context: nil, schema: nil, model: nil, strict: nil, return_meta: false,
                   system: nil, images: nil, think: nil, return_reasoning: false, keep_alive: nil, suffix: nil, raw: nil,
                   options: nil, hooks: {}, tools: nil)
        params = Params::Generate.new(
          prompt: prompt, context: context, schema: schema, model: model, strict: strict,
          return_meta: return_meta, system: system, images: images, think: think,
          return_reasoning: return_reasoning, keep_alive: keep_alive, suffix: suffix,
          raw: raw, options: options, hooks: hooks, tools: tools
        )
        generate_with_params(params)
      end

      # @param params [Ollama::Params::Generate] Generate parameters
      # @return [String, Hash] Response data (String without schema, Hash with schema)
      # rubocop:disable Metrics/AbcSize
      def generate_with_params(params)
        raise ArgumentError, "prompt is required" if params.prompt.nil?

        strict = params.strict.nil? ? @config.strict_json : params.strict

        validate_thinking_capability!(params.model, params.think)

        @summarize_schema_cache = {}
        formatter = ResponseFormatter.new(provider: @provider, config: @config, schema_cache: @summarize_schema_cache)

        attempts = 0
        started_at = monotonic_time
        current_prompt = build_prompt(params.prompt, params.think, params.return_reasoning)
        pulled_models = []

        begin
          attempts += 1
          raw_response, final_context = call_generate_api(
            prompt: current_prompt, context: params.context, schema: params.schema, model: params.model, hooks: params.hooks,
            system: params.system, images: params.images, think: params.think, keep_alive: params.keep_alive,
            suffix: params.suffix, raw: params.raw, options: params.options
          )

          emit_response_hook(raw_response,
                             endpoint: "/api/generate", model: params.model || @config.model, attempt: attempts)

          response_data = formatter.process(raw_response, params.schema, params.think, params.return_reasoning)
          formatter.format(response_data, final_context, params.return_meta, params.model || @config.model, attempts, started_at)
        rescue RateLimitExhaustedError => e
          raise e
        rescue NotFoundError => e
          target_model = params.model || @config.model
          raise enhance_not_found_error(e) if pulled_models.include?(target_model) || attempts > @config.retries

          pull(target_model)
          pulled_models << target_model
          retry
        rescue TimeoutError => e
          raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

          sleep(2**attempts)
          retry
        rescue InvalidJSONError, SchemaViolationError, ThinkingFormatError => e
          raise e if strict
          raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

          repair_msg = "CRITICAL FIX: Your last response was invalid or violated the schema. " \
                       "Error: #{e.message}. Return ONLY valid JSON."
          current_prompt = "#{current_prompt}\n\n#{repair_msg}"
          retry
        rescue HTTPError => e
          raise e unless e.retryable?
          raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

          retry
        rescue Error => e
          raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

          retry
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists, Metrics/AbcSize

      THINK_PROMPT = "Think step-by-step using 思考 tags.\n\n"

      private

      def validate_thinking_capability!(model, think)
        return unless think
        return if Ollama::Capabilities.for("name" => model || @config.model)["thinking"]

        raise UnsupportedThinkingModel, "Model #{model || @config.model} is not marked as reasoning-capable"
      end

      def build_prompt(prompt, thinking, _return_reasoning)
        return prompt unless thinking

        "#{THINK_PROMPT}#{prompt}"
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
      # rubocop:disable Metrics/ParameterLists
      def call_generate_api(prompt:, context:, schema:, model:, hooks:, system: nil, images: nil,
                            think: nil, keep_alive: nil, suffix: nil, raw: nil, options: nil)
        config_model = @config.model
        config_timeout = @config.timeout
        base_url = @config.base_url

        @provider.generate_endpoint
        stream_enabled = streaming_requested?(hooks)

        request_params = {
          model: model || config_model,
          prompt: prompt,
          stream: stream_enabled,
          options: build_options(options)
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

        request = Request.new(
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

        serializer = Serializers::Generate.new
        transport_req = serializer.call(request)

        full_response = +""
        final_context = nil

        begin
          with_rate_limit_key_rotation do |api_key|
            full_response = +""
            final_context = nil
            @config.apply_auth_to(transport_req, api_key: api_key) if transport_req.is_a?(Transport::Request)

            if stream_enabled
              buffer = +""
              handler = GenerateStreamHandler.new(nil, hooks, full_response, provider: @provider)
              @pipeline.stream(transport_req) do |chunk|
                handler.send(:drain_chunk, buffer, chunk)
              end
            else
              transport_response = @pipeline.call(transport_req)
              if transport_response.raw && !transport_response.raw.is_a?(Net::HTTPSuccess)
                handle_http_error(transport_response.raw,
                                  requested_model: model || config_model)
              end

              parser = Parsers::Generate.new(provider: @provider)
              parsed_response = parser.call(transport_response)
              full_response = parsed_response.message.content
              final_context = parsed_response.context
            end
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          hooks[:on_error]&.call(e)
          raise TimeoutError, "Request timed out after #{config_timeout}s"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          hooks[:on_error]&.call(e)
          raise Error, "Connection failed: #{e.message}"
        rescue Error => e
          hooks[:on_error]&.call(e)
          raise e
        end

        [full_response, final_context]
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse API response: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
      # rubocop:enable Metrics/ParameterLists

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
        return @summarize_schema_cache[cache_key] if @summarize_schema_cache.key?(cache_key)

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
        @summarize_schema_cache[cache_key] = result
        result
      end

      def streaming_requested?(hooks)
        !(hooks[:on_token] || hooks[:on_error] || hooks[:on_complete]).nil?
      end

      def enhance_not_found_error(error)
        return error if error.requested_model.nil?

        begin
          available_models = list_model_names
          suggestions = find_similar_models(error.requested_model, available_models)
          NotFoundError.new(error.message, requested_model: error.requested_model, suggestions: suggestions)
        rescue Error
          error
        end
      end

      def find_similar_models(requested, available, limit: 5)
        return [] if available.empty?

        requested_lower = requested.downcase
        matches = available.select do |model|
          model_lower = model.downcase
          model_lower.include?(requested_lower) || requested_lower.include?(model_lower)
        end

        if matches.empty?
          requested_parts = requested_lower.split(/[:._-]/)
          matches = available.select do |model|
            model_parts = model.downcase.split(/[:._-]/)
            requested_parts.any? { |part| model_parts.any? { |mp| mp.include?(part) || part.include?(mp) } }
          end
        end

        matches.first(limit)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1000.0).round(1)
      end
    end
  end
end

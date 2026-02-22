# frozen_string_literal: true

module Ollama
  class Client
    # Generate completion endpoint with auto-pull, retries, and structured output
    module Generate # rubocop:disable Metrics/ModuleLength
      # @param prompt [String] Text for the model to generate a response from (required)
      # @param schema [Hash, nil] JSON Schema for structured output; also sets format
      # @param model [String, nil] Model name override
      # @param strict [Boolean] Enable strict JSON validation + repair retries
      # @param return_meta [Boolean] When true, wraps response with metadata
      # @param system [String, nil] System prompt
      # @param images [Array<String>, nil] Base64-encoded images for vision models
      # @param think [Boolean, String, nil] Enable thinking output (true/false/"high"/"medium"/"low")
      # @param keep_alive [String, nil] Model keep-alive duration (e.g. "5m", "0")
      # @param suffix [String, nil] Fill-in-the-middle text after prompt
      # @param raw [Boolean, nil] When true, skip prompt templating
      # @param options [Hash, nil] Runtime options (temperature, top_p, num_ctx, etc.)
      # @param hooks [Hash] Streaming callbacks (:on_token, :on_error, :on_complete)
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
      def generate(prompt:, schema: nil, model: nil, strict: @config.strict_json, return_meta: false,
                   system: nil, images: nil, think: nil, keep_alive: nil, suffix: nil, raw: nil,
                   options: nil, hooks: {})
        raise ArgumentError, "prompt is required" if prompt.nil?

        attempts = 0
        started_at = monotonic_time
        current_prompt = prompt
        pulled_models = []

        begin
          attempts += 1
          raw_response = call_generate_api(
            prompt: current_prompt, schema: schema, model: model, hooks: hooks,
            system: system, images: images, think: think, keep_alive: keep_alive,
            suffix: suffix, raw: raw, options: options
          )

          response_data = schema ? parse_and_validate_schema_response(raw_response, schema) : raw_response

          return response_data unless return_meta

          {
            "data" => response_data,
            "meta" => {
              "endpoint" => "/api/generate",
              "model" => model || @config.model,
              "attempts" => attempts,
              "latency_ms" => elapsed_ms(started_at)
            }
          }
        rescue NotFoundError => e
          target_model = model || @config.model
          raise enhance_not_found_error(e) if pulled_models.include?(target_model) || attempts > @config.retries

          pull(target_model)
          pulled_models << target_model
          retry
        rescue TimeoutError => e
          raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

          sleep(2**attempts)
          retry
        rescue InvalidJSONError, SchemaViolationError => e
          raise e if strict && attempts > @config.retries
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
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists

      private

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
      def call_generate_api(prompt:, schema:, model:, hooks:, system: nil, images: nil,
                            think: nil, keep_alive: nil, suffix: nil, raw: nil, options: nil)
        generate_uri = URI("#{@config.base_url}/api/generate")
        req = Net::HTTP::Post.new(generate_uri)
        req["Content-Type"] = "application/json"

        stream_enabled = !(hooks[:on_token] || hooks[:on_error] || hooks[:on_complete]).nil?

        body = {
          model: model || @config.model,
          prompt: prompt,
          stream: stream_enabled,
          options: build_options(options)
        }

        body[:system] = system if system
        body[:images] = images if images
        body[:think] = think unless think.nil?
        body[:keep_alive] = keep_alive if keep_alive
        body[:suffix] = suffix if suffix
        body[:raw] = raw unless raw.nil?

        if schema
          body[:format] = schema
          body[:prompt] = enhance_prompt_for_json(prompt, schema)
        end

        req.body = body.to_json

        full_response = +""

        begin
          Net::HTTP.start(generate_uri.hostname, generate_uri.port,
                          read_timeout: @config.timeout, open_timeout: @config.timeout) do |h|
            h.request(req) do |res|
              handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

              if stream_enabled
                handle_generate_stream(res, hooks, full_response)
              else
                response_body = JSON.parse(res.body)
                full_response = response_body["response"]
              end
            end
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          hooks[:on_error]&.call(e)
          raise TimeoutError, "Request timed out after #{@config.timeout}s"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          hooks[:on_error]&.call(e)
          raise Error, "Connection failed: #{e.message}"
        rescue StandardError => e
          hooks[:on_error]&.call(e)
          raise e
        end

        full_response
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse API response: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists

      def handle_generate_stream(res, hooks, full_response)
        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          while (newline_idx = buffer.index("\n"))
            line = buffer.slice!(0, newline_idx + 1).strip
            next if line.empty?

            begin
              obj = JSON.parse(line)

              if obj["error"]
                error = StreamError.new(obj["error"])
                hooks[:on_error]&.call(error)
                raise error
              end

              token = obj["response"]
              if token
                full_response << token
                hooks[:on_token]&.call(token)
              end

              hooks[:on_complete]&.call if obj["done"]
            rescue JSON::ParserError
              # Ignore malformed stream chunks silently
            end
          end
        end
      end

      def parse_and_validate_schema_response(raw, schema)
        parsed = parse_json_response(raw)
        raise SchemaViolationError, "Empty or nil response when schema is required" if parsed.nil? || parsed.empty?

        SchemaValidator.validate!(parsed, schema)
        parsed
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
        "Required fields: [#{required_list}]. Example structure:\n#{example_json}"
      end

      def parse_json_response(raw)
        json_text = extract_json_fragment(raw)
        JSON.parse(json_text)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse extracted JSON: #{e.message}. Extracted: #{json_text&.slice(0, 200)}..."
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def extract_json_fragment(text)
        raise InvalidJSONError, "Empty response body" if text.nil? || text.empty?

        stripped = text.lstrip
        if stripped.start_with?("{", "[", "\"", "-", "t", "f", "n") || stripped.match?(/\A\d/)
          begin
            JSON.parse(stripped)
            return stripped
          rescue JSON::ParserError
            # Fall back to extraction below
          end
        end

        start_idx = text.index(/[{\[]/)
        raise InvalidJSONError, "No JSON found in response. Response: #{text[0..200]}..." unless start_idx

        stack = []
        in_string = false
        escape = false

        i = start_idx
        while i < text.length
          ch = text.getbyte(i)

          if in_string
            if escape
              escape = false
            elsif ch == 92 # backslash
              escape = true
            elsif ch == 34 # double-quote
              in_string = false
            end
          else
            case ch
            when 34 then in_string = true # double-quote
            when 123 then stack << 125 # { -> }
            when 91 then stack << 93 # [ -> ]
            when 125, 93 # }, ]
              expected = stack.pop
              raise InvalidJSONError, "Malformed JSON. Response: #{text[start_idx, 200]}..." if expected != ch

              return text[start_idx..i] if stack.empty?
            end
          end

          i += 1
        end

        raise InvalidJSONError, "Incomplete JSON in response. Response: #{text[start_idx, 200]}..."
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

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

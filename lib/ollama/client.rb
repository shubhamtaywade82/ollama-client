# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"
require_relative "embeddings"
require_relative "response"

module Ollama
  # Main client class for interacting with Ollama API
  class Client
    attr_reader :embeddings

    def initialize(config: nil)
      @config = config || default_config
      @uri = URI("#{@config.base_url}/api/generate")
      @base_uri = URI(@config.base_url)
      @embeddings = Embeddings.new(@config)
    end

    # Core generate method for prompt -> completion
    # Includes strict json validation, model auto-pull, and timeout retries.
    # Hooks can optionally include `on_token`, `on_error`, `on_complete` (callables)
    # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def generate(prompt:, schema: nil, model: nil, strict: @config.strict_json, return_meta: false, hooks: {})
      raise ArgumentError, "prompt is required" if prompt.nil?

      attempts = 0
      started_at = monotonic_time
      current_prompt = prompt
      pulled_models = []

      begin
        attempts += 1
        raw = call_generate_api(prompt: current_prompt, schema: schema, model: model, hooks: hooks)

        response_data = schema ? parse_and_validate_schema_response(raw, schema) : raw

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
        # 404 Model Not Found -> attempt pull once
        raise enhance_not_found_error(e) if pulled_models.include?(target_model) || attempts > @config.retries

        pull(target_model)
        pulled_models << target_model
        retry
      rescue TimeoutError => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        # Exponential backoff
        sleep(2**attempts)
        retry
      rescue InvalidJSONError, SchemaViolationError => e
        raise e if strict && attempts > @config.retries
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        # Structured retry with repair prompt
        repair_msg = "CRITICAL FIX: Your last response was invalid or violated the schema. Error: #{e.message}. Return ONLY valid JSON."
        current_prompt = "#{current_prompt}\n\n#{repair_msg}"
        retry
      rescue HTTPError => e
        # Fast fail if non-retryable
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Pull a model explicitly
    def pull(model_name)
      pull_uri = URI("#{@config.base_url}/api/pull")
      req = Net::HTTP::Post.new(pull_uri)
      req["Content-Type"] = "application/json"
      req.body = { model: model_name, stream: false }.to_json

      # Pulls can take much longer, increase timeout multiplier
      res = Net::HTTP.start(
        pull_uri.hostname,
        pull_uri.port,
        read_timeout: @config.timeout * 10,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      handle_http_error(res, requested_model: model_name) unless res.is_a?(Net::HTTPSuccess)
      true
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Pull request timed out"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed during pull: #{e.message}"
    end

    # Public method to list available models
    def list_models
      tags_uri = URI("#{@config.base_url}/api/tags")
      req = Net::HTTP::Get.new(tags_uri)

      res = Net::HTTP.start(
        tags_uri.hostname,
        tags_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      raise Error, "Failed to fetch models: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      body = JSON.parse(res.body)
      body["models"]&.map { |m| m["name"] } || []
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse models response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
    alias tags list_models

    private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def call_generate_api(prompt:, schema:, model:, hooks:)
      req = Net::HTTP::Post.new(@uri)
      req["Content-Type"] = "application/json"

      stream_enabled = !(hooks[:on_token] || hooks[:on_error] || hooks[:on_complete]).nil?

      body = {
        model: model || @config.model,
        prompt: prompt,
        stream: stream_enabled,
        temperature: @config.temperature,
        top_p: @config.top_p,
        num_ctx: @config.num_ctx
      }

      if schema
        body[:format] = schema
        body[:prompt] = enhance_prompt_for_json(prompt, schema)
      end

      req.body = body.to_json

      full_response = +""

      begin
        Net::HTTP.start(@uri.hostname, @uri.port, read_timeout: @config.timeout, open_timeout: @config.timeout) do |h|
          h.request(req) do |res|
            handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

            if stream_enabled
              buffer = +""
              res.read_body do |chunk|
                buffer << chunk
                while (newline_idx = buffer.index("\n"))
                  line = buffer.slice!(0, newline_idx + 1).strip
                  next if line.empty?

                  begin
                    obj = JSON.parse(line)
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
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
          when 34 # double-quote
            in_string = true
          when 123 # {
            stack << 125 # }
          when 91 # [
            stack << 93 # ]
          when 125, 93 # }, ]
            expected = stack.pop
            raise InvalidJSONError, "Malformed JSON in const. Response: #{text[start_idx, 200]}..." if expected != ch

            return text[start_idx..i] if stack.empty?
          end
        end

        i += 1
      end

      raise InvalidJSONError, "Incomplete JSON in response. Response: #{text[start_idx, 200]}..."
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def default_config
      if defined?(OllamaClient)
        OllamaClient.config.dup
      else
        Config.new
      end
    end

    def handle_http_error(res, requested_model: nil)
      status_code = res.code.to_i
      requested_model ||= @config.model

      raise NotFoundError.new(res.message, requested_model: requested_model) if status_code == 404

      # HTTPError retryable handles 408, 429, 500, 502, 503
      raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
    end

    def enhance_not_found_error(error)
      return error if error.requested_model.nil?

      begin
        available_models = list_models
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

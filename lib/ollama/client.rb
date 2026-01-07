# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"
require_relative "tool_intent"
require_relative "schemas/tool_intent"
require_relative "prompts/tool_planner"

module Ollama
  # Main client class for interacting with Ollama API
  class Client
    def initialize(config: nil)
      @config = config || default_config
      @uri = URI("#{@config.base_url}/api/generate")
      @chat_uri = URI("#{@config.base_url}/api/chat")
    end

    # Chat API method matching JavaScript ollama.chat() interface
    # Supports structured outputs via format parameter
    #
    # @param model [String] Model name (overrides config.model)
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param format [Hash, nil] JSON Schema for structured outputs
    # @param options [Hash, nil] Additional options (temperature, top_p, etc.)
    # @return [Hash] Parsed and validated JSON response matching the format schema
    def chat(messages:, model: nil, format: nil, options: {})
      attempts = 0
      @current_schema = format # Store for validation

      begin
        attempts += 1
        raw = call_chat_api(model: model, messages: messages, format: format, options: options)
        parsed = parse_json_response(raw)

        # CRITICAL: If format is provided, free-text output is forbidden
        if format
          raise SchemaViolationError, "Empty or nil response when format schema is required" if parsed.nil? || parsed.empty?
          SchemaValidator.validate!(parsed, format)
        end

        parsed
      rescue NotFoundError => e
        enhanced_error = enhance_not_found_error(e)
        raise enhanced_error
      rescue HTTPError => e
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, InvalidJSONError, SchemaViolationError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end

    def generate(prompt:, schema:)
      attempts = 0
      @current_schema = schema # Store for prompt enhancement

      begin
        attempts += 1
        raw = call_api(prompt)
        parsed = parse_json_response(raw)

        # CRITICAL: If schema is provided, free-text output is forbidden
        raise SchemaViolationError, "Empty or nil response when schema is required" if parsed.nil? || parsed.empty?
        SchemaValidator.validate!(parsed, schema)
        parsed
      rescue NotFoundError => e
        # 404 errors are never retried, but we can suggest models
        enhanced_error = enhance_not_found_error(e)
        raise enhanced_error
      rescue HTTPError => e
        # Don't retry non-retryable HTTP errors (400, etc.)
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, InvalidJSONError, SchemaViolationError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end

    # Generate a schema-validated tool intent (no execution).
    #
    # @param prompt [String] Task description for planner
    # @param tools [Array<Hash>] Array of tools with :name and :description
    # @param rules [Array<String>] Optional additional rules for planner
    # @return [Ollama::ToolIntent] Typed intent object
    def generate_tool_intent(prompt:, tools:, rules: [])
      planner_prompt =
        Ollama::Prompts.tool_planner(
          tools: tools,
          rules: rules
        ) + "\n\nTask:\n#{prompt}"

      result = generate(
        prompt: planner_prompt,
        schema: Ollama::Schemas.tool_intent
      )

      Ollama::ToolIntent.new(
        action: result["action"],
        input: result["input"] || {}
      )
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

    private

    def default_config
      if defined?(OllamaClient)
        OllamaClient.config
      else
        Config.new
      end
    end

    def enhance_not_found_error(error)
      return error if error.requested_model.nil?

      begin
        available_models = list_models
        suggestions = find_similar_models(error.requested_model, available_models)
        NotFoundError.new(error.message, requested_model: error.requested_model, suggestions: suggestions)
      rescue Error
        # If we can't fetch models, return original error
        error
      end
    end

    def enhance_prompt_for_json(prompt)
      return prompt unless @current_schema

      # Add JSON instruction if not already present
      return prompt if prompt.match?(/json|JSON/i)

      schema_summary = summarize_schema(@current_schema)
      json_instruction = "CRITICAL: Respond with ONLY valid JSON (no markdown code blocks, no explanations). " \
                         "The JSON must include these exact required fields: #{schema_summary}"
      "#{prompt}\n\n#{json_instruction}"
    end

    def summarize_schema(schema)
      return "object" unless schema.is_a?(Hash)

      required = schema["required"] || []
      properties = schema["properties"] || {}
      return "object" if required.empty? && properties.empty?

      # Create example JSON structure
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
      # CRITICAL: Never parse raw text directly - extract JSON first
      # Ollama can return leading text, markdown fences, or explanations
      json_start = raw.index("{")
      json_end = raw.rindex("}")

      unless json_start && json_end && json_end > json_start
        raise InvalidJSONError, "No JSON object found in response. Response: #{raw[0..200]}..."
      end

      # Extract only the JSON portion
      json_text = raw[json_start..json_end]
      begin
        JSON.parse(json_text)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse extracted JSON: #{e.message}. Extracted: #{json_text[0..200]}..."
      end
    end

    def find_similar_models(requested, available, limit: 5)
      return [] if available.empty?

      # Simple similarity: models containing the requested name or vice versa
      requested_lower = requested.downcase
      matches = available.select do |model|
        model_lower = model.downcase
        model_lower.include?(requested_lower) || requested_lower.include?(model_lower)
      end

      # Also try fuzzy matching on model name parts
      if matches.empty?
        requested_parts = requested_lower.split(/[:._-]/)
        matches = available.select do |model|
          model_parts = model.downcase.split(/[:._-]/)
          requested_parts.any? { |part| model_parts.any? { |mp| mp.include?(part) || part.include?(mp) } }
        end
      end

      matches.first(limit)
    end

    def call_chat_api(model:, messages:, format:, options:)
      req = Net::HTTP::Post.new(@chat_uri)
      req["Content-Type"] = "application/json"

      # Build request body
      body = {
        model: model || @config.model,
        messages: messages,
        stream: false
      }

      # Merge options (temperature, top_p, etc.) with config defaults
      body_options = {
        temperature: options[:temperature] || @config.temperature,
        top_p: options[:top_p] || @config.top_p,
        num_ctx: options[:num_ctx] || @config.num_ctx
      }
      body[:options] = body_options

      # Use Ollama's native format parameter for structured outputs
      body[:format] = format if format

      req.body = body.to_json

      res = Net::HTTP.start(
        @chat_uri.hostname,
        @chat_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPSuccess)
        status_code = res.code.to_i
        requested_model = model || @config.model

        # Explicit HTTP error handling with hard retry rules
        case status_code
        when 404
          raise NotFoundError.new(res.message, requested_model: requested_model)
        when 400, 401, 403
          # Client errors: never retry
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        when 408, 429, 500, 503
          # Retryable errors: will be retried by caller
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        else
          # Other 4xx/5xx: default to non-retryable for safety
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        end
      end

      response_body = JSON.parse(res.body)
      # Chat API returns message.content, not response
      response_body["message"]["content"]
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse API response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    def call_api(prompt)
      req = Net::HTTP::Post.new(@uri)
      req["Content-Type"] = "application/json"

      # Build request body
      body = {
        model: @config.model,
        prompt: prompt,
        stream: false,
        temperature: @config.temperature,
        top_p: @config.top_p,
        num_ctx: @config.num_ctx
      }

      # Use Ollama's native format parameter for structured outputs
      if @current_schema
        body[:format] = @current_schema
        # Also enhance prompt as fallback (some models work better with both)
        body[:prompt] = enhance_prompt_for_json(prompt)
      end

      req.body = body.to_json

      res = Net::HTTP.start(
        @uri.hostname,
        @uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPSuccess)
        status_code = res.code.to_i

        # Explicit HTTP error handling with hard retry rules
        case status_code
        when 404
          raise NotFoundError.new(res.message, requested_model: @config.model)
        when 400, 401, 403
          # Client errors: never retry
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        when 408, 429, 500, 503
          # Retryable errors: will be retried by caller
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        else
          # Other 4xx/5xx: default to non-retryable for safety
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        end
      end

      body = JSON.parse(res.body)
      body["response"]
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse API response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
  end
end

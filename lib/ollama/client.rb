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
  # rubocop:disable Metrics/ClassLength
  class Client
    def initialize(config: nil)
      @config = config || default_config
      @uri = URI("#{@config.base_url}/api/generate")
      @chat_uri = URI("#{@config.base_url}/api/chat")
      @base_uri = URI(@config.base_url)
      @embeddings = Embeddings.new(@config)
    end

    # Access embeddings API
    #
    # Example:
    #   client = Ollama::Client.new
    #   embedding = client.embeddings.embed(model: "all-minilm", input: "What is Ruby?")
    attr_reader :embeddings

    # Chat API method matching JavaScript ollama.chat() interface
    # Supports structured outputs via format parameter
    #
    # ⚠️ WARNING: chat() is NOT recommended for agent planning or tool routing.
    # Use generate() instead for stateless, explicit state injection.
    #
    # @param model [String] Model name (overrides config.model)
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param format [Hash, nil] JSON Schema for structured outputs
    # @param tools [Tool, Array<Tool>, Array<Hash>, nil] Tool definition(s) - can be Tool object(s) or hash(es)
    # @param options [Hash, nil] Additional options (temperature, top_p, etc.)
    # @param strict [Boolean] If true, requires explicit opt-in and disables retries on schema violations
    # @param include_meta [Boolean] If true, returns hash with :data and :meta keys
    # @return [Hash] Parsed and validated JSON response matching the format schema
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/ParameterLists
    def chat(messages:, model: nil, format: nil, tools: nil, options: {}, strict: false, allow_chat: false,
             return_meta: false)
      ensure_chat_allowed!(allow_chat: allow_chat, strict: strict, method_name: "chat")

      attempts = 0
      @current_schema = format # Store for validation
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        normalized_tools = normalize_tools(tools)
        raw = call_chat_api(model: model, messages: messages, format: format, tools: normalized_tools, options: options)
        attempt_latency_ms = elapsed_ms(attempt_started_at)

        emit_response_hook(raw, chat_response_meta(model: model, attempt: attempts,
                                                   attempt_latency_ms: attempt_latency_ms))

        empty_response = empty_chat_response(raw: raw,
                                             return_meta: return_meta,
                                             model: model,
                                             attempts: attempts,
                                             started_at: started_at)
        return empty_response unless empty_response.nil?

        parsed = parse_json_response(raw)
        validate_chat_format!(parsed: parsed, format: format)

        return parsed unless return_meta

        chat_response_with_meta(data: parsed, model: model, attempts: attempts, started_at: started_at)
      rescue NotFoundError => e
        enhanced_error = enhance_not_found_error(e)
        raise enhanced_error
      rescue HTTPError => e
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue InvalidJSONError, SchemaViolationError => e
        raise e if strict
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end
    # rubocop:enable Metrics/ParameterLists

    # Raw Chat API method that returns the full parsed response body.
    #
    # This is intended for advanced use cases such as tool-calling loops where
    # callers need access to fields like `message.tool_calls`.
    #
    # @param model [String] Model name (overrides config.model)
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param format [Hash, nil] JSON Schema for structured outputs (validates message.content JSON when present)
    # @param tools [Tool, Array<Tool>, Array<Hash>, nil] Tool definition(s) - can be Tool object(s) or hash(es)
    # @param options [Hash, nil] Additional options (temperature, top_p, etc.)
    # @return [Hash] Full parsed JSON response body from Ollama with access to message.tool_calls
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
    def chat_raw(messages:, model: nil, format: nil, tools: nil, options: {}, strict: false, allow_chat: false,
                 return_meta: false, stream: false, &on_chunk)
      ensure_chat_allowed!(allow_chat: allow_chat, strict: strict, method_name: "chat_raw")

      attempts = 0
      @current_schema = format # Store for validation
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        normalized_tools = normalize_tools(tools)
        raw_body =
          if stream
            call_chat_api_raw_stream(
              model: model,
              messages: messages,
              format: format,
              tools: normalized_tools,
              options: options,
              &on_chunk
            )
          else
            call_chat_api_raw(model: model, messages: messages, format: format, tools: normalized_tools,
                              options: options)
          end
        attempt_latency_ms = elapsed_ms(attempt_started_at)

        emit_response_hook(
          raw_body.is_a?(Hash) ? raw_body.to_json : raw_body,
          {
            endpoint: "/api/chat",
            model: model || @config.model,
            attempt: attempts,
            attempt_latency_ms: attempt_latency_ms
          }
        )

        # `raw_body` is either a JSON string (non-stream) or a Hash (stream).
        parsed_body = raw_body.is_a?(Hash) ? raw_body : JSON.parse(raw_body)

        # If a format schema is provided, validate the assistant content JSON (when present).
        if format
          content = parsed_body.dig("message", "content")
          if content.nil? || content.empty?
            raise SchemaViolationError,
                  "Empty or nil response when format schema is required"
          end

          parsed_content = parse_json_response(content)
          if parsed_content.nil? || parsed_content.empty?
            raise SchemaViolationError,
                  "Empty or nil response when format schema is required"
          end

          SchemaValidator.validate!(parsed_content, format)
        end

        # Wrap in Response object for method access (e.g., response.message&.tool_calls)
        response_obj = Response.new(parsed_body)

        return response_obj unless return_meta

        {
          "data" => response_obj,
          "meta" => {
            "endpoint" => "/api/chat",
            "model" => model || @config.model,
            "attempts" => attempts,
            "latency_ms" => elapsed_ms(started_at)
          }
        }
      rescue NotFoundError => e
        enhanced_error = enhance_not_found_error(e)
        raise enhanced_error
      rescue HTTPError => e
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse API response: #{e.message}" if strict
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue InvalidJSONError, SchemaViolationError => e
        raise e if strict
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists

    def generate(prompt:, schema:, model: nil, strict: false, return_meta: false)
      attempts = 0
      @current_schema = schema # Store for prompt enhancement
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        raw = call_api(prompt, model: model)
        attempt_latency_ms = elapsed_ms(attempt_started_at)

        emit_response_hook(
          raw,
          {
            endpoint: "/api/generate",
            model: model || @config.model,
            attempt: attempts,
            attempt_latency_ms: attempt_latency_ms
          }
        )

        parsed = parse_json_response(raw)

        # CRITICAL: If schema is provided, free-text output is forbidden
        raise SchemaViolationError, "Empty or nil response when schema is required" if parsed.nil? || parsed.empty?

        SchemaValidator.validate!(parsed, schema)
        return parsed unless return_meta

        {
          "data" => parsed,
          "meta" => {
            "endpoint" => "/api/generate",
            "model" => model || @config.model,
            "attempts" => attempts,
            "latency_ms" => elapsed_ms(started_at)
          }
        }
      rescue NotFoundError => e
        # 404 errors are never retried, but we can suggest models
        enhanced_error = enhance_not_found_error(e)
        raise enhanced_error
      rescue HTTPError => e
        # Don't retry non-retryable HTTP errors (400, etc.)
        raise e unless e.retryable?
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue InvalidJSONError, SchemaViolationError => e
        raise e if strict
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end
    # rubocop:enable Metrics/MethodLength

    def generate_strict!(prompt:, schema:, model: nil, return_meta: false)
      generate(prompt: prompt, schema: schema, model: model, strict: true, return_meta: return_meta)
    end

    # Lightweight server health check.
    # Returns true/false by default; pass return_meta: true for details.
    # rubocop:disable Metrics/MethodLength
    def health(return_meta: false)
      ping_uri = URI.join(@base_uri.to_s.end_with?("/") ? @base_uri.to_s : "#{@base_uri}/", "api/ping")
      started_at = monotonic_time

      req = Net::HTTP::Get.new(ping_uri)
      res = Net::HTTP.start(
        ping_uri.hostname,
        ping_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      ok = res.is_a?(Net::HTTPSuccess)
      return ok unless return_meta

      {
        "ok" => ok,
        "meta" => {
          "endpoint" => "/api/ping",
          "status_code" => res.code.to_i,
          "latency_ms" => elapsed_ms(started_at)
        }
      }
    rescue Net::ReadTimeout, Net::OpenTimeout
      return false unless return_meta

      {
        "ok" => false,
        "meta" => {
          "endpoint" => "/api/ping",
          "error" => "timeout",
          "latency_ms" => elapsed_ms(started_at)
        }
      }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      return false unless return_meta

      {
        "ok" => false,
        "meta" => {
          "endpoint" => "/api/ping",
          "error" => e.message,
          "latency_ms" => elapsed_ms(started_at)
        }
      }
    end
    # rubocop:enable Metrics/MethodLength

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

    def ensure_chat_allowed!(allow_chat:, strict:, method_name:)
      return if allow_chat || strict

      raise Error,
            "#{method_name}() is intentionally gated because it is easy to misuse inside agents. " \
            "Prefer generate(). If you really want #{method_name}(), pass allow_chat: true (or strict: true)."
    end

    # Normalize tools to array of hashes for API
    # Supports: Tool object, Array of Tool objects, Array of hashes, or nil
    def normalize_tools(tools)
      return nil if tools.nil?

      # Single Tool object
      return [tools.to_h] if tools.is_a?(Tool)

      # Array of tools
      if tools.is_a?(Array)
        return tools.map { |t| t.is_a?(Tool) ? t.to_h : t }
      end

      # Already a hash (shouldn't happen, but handle gracefully)
      tools
    end

    def chat_response_meta(model:, attempt:, attempt_latency_ms:)
      {
        endpoint: "/api/chat",
        model: model || @config.model,
        attempt: attempt,
        attempt_latency_ms: attempt_latency_ms
      }
    end

    def empty_chat_response(raw:, return_meta:, model:, attempts:, started_at:)
      return nil unless raw.nil? || raw.empty?
      return "" unless return_meta

      {
        "data" => "",
        "meta" => {
          "endpoint" => "/api/chat",
          "model" => model || @config.model,
          "attempts" => attempts,
          "latency_ms" => elapsed_ms(started_at),
          "note" => "Empty content (likely tool_calls only - use chat_raw() to access tool_calls)"
        }
      }
    end

    def validate_chat_format!(parsed:, format:)
      return unless format
      if parsed.nil? || parsed.empty?
        raise SchemaViolationError, "Empty or nil response when format schema is required"
      end

      SchemaValidator.validate!(parsed, format)
    end

    def chat_response_with_meta(data:, model:, attempts:, started_at:)
      {
        "data" => data,
        "meta" => {
          "endpoint" => "/api/chat",
          "model" => model || @config.model,
          "attempts" => attempts,
          "latency_ms" => elapsed_ms(started_at)
        }
      }
    end

    def handle_http_error(res, requested_model: nil)
      status_code = res.code.to_i
      requested_model ||= @config.model

      raise NotFoundError.new(res.message, requested_model: requested_model) if status_code == 404

      # All other errors use HTTPError
      # Retryable: 408, 429, 500, 503 (handled by HTTPError#retryable?)
      # Non-retryable: 400-403, 405-407, 409-428, 430-499, 501, 504-599
      raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
    end

    def default_config
      if defined?(OllamaClient)
        # Avoid sharing a mutable global config object across clients/threads.
        # The OllamaClient.config instance remains global for convenience,
        # but each Client gets its own copy by default.
        OllamaClient.config.dup
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
      json_text = extract_json_fragment(raw)
      JSON.parse(json_text)
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse extracted JSON: #{e.message}. Extracted: #{json_text&.slice(0, 200)}..."
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def extract_json_fragment(text)
      raise InvalidJSONError, "Empty response body" if text.nil? || text.empty?

      stripped = text.lstrip

      # Fast path: the whole (trimmed) body is valid JSON (including primitives).
      if stripped.start_with?("{", "[", "\"", "-", "t", "f", "n") || stripped.match?(/\A\d/)
        begin
          JSON.parse(stripped)
          return stripped
        rescue JSON::ParserError
          # Fall back to extraction below (common with prefix/suffix noise).
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
            raise InvalidJSONError, "Malformed JSON in response. Response: #{text[start_idx, 200]}..." if expected != ch
            return text[start_idx..i] if stack.empty?
          end
        end

        i += 1
      end

      raise InvalidJSONError, "Incomplete JSON in response. Response: #{text[start_idx, 200]}..."
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def emit_response_hook(raw, meta)
      hook = @config.on_response
      return unless hook.respond_to?(:call)

      hook.call(raw, meta)
    rescue StandardError
      # Observability hooks must never break the main flow.
      nil
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_time - started_at) * 1000.0).round(1)
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

    def call_chat_api(model:, messages:, format:, tools:, options:)
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
      body[:tools] = tools if tools

      req.body = body.to_json

      res = Net::HTTP.start(
        @chat_uri.hostname,
        @chat_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

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

    def call_api(prompt, model: nil)
      req = Net::HTTP::Post.new(@uri)
      req["Content-Type"] = "application/json"

      # Build request body
      body = {
        model: model || @config.model,
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

      handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

      body = JSON.parse(res.body)
      body["response"]
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse API response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    def call_chat_api_raw(model:, messages:, format:, tools:, options:)
      req = Net::HTTP::Post.new(@chat_uri)
      req["Content-Type"] = "application/json"

      body = {
        model: model || @config.model,
        messages: messages,
        stream: false
      }

      body_options = {
        temperature: options[:temperature] || @config.temperature,
        top_p: options[:top_p] || @config.top_p,
        num_ctx: options[:num_ctx] || @config.num_ctx
      }
      body[:options] = body_options

      body[:format] = format if format
      body[:tools] = tools if tools

      req.body = body.to_json

      res = Net::HTTP.start(
        @chat_uri.hostname,
        @chat_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) { |http| http.request(req) }

      handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

      res.body
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
    def call_chat_api_raw_stream(model:, messages:, format:, tools:, options:)
      # tools should already be normalized by caller
      req = Net::HTTP::Post.new(@chat_uri)
      req["Content-Type"] = "application/json"

      body = {
        model: model || @config.model,
        messages: messages,
        stream: true
      }

      body_options = {
        temperature: options[:temperature] || @config.temperature,
        top_p: options[:top_p] || @config.top_p,
        num_ctx: options[:num_ctx] || @config.num_ctx
      }
      body[:options] = body_options

      body[:format] = format if format
      body[:tools] = tools if tools

      req.body = body.to_json

      final_obj = nil
      aggregated = {
        "message" => {
          "role" => "assistant",
          "content" => +""
        }
      }

      buffer = +""

      Net::HTTP.start(
        @chat_uri.hostname,
        @chat_uri.port,
        read_timeout: @config.timeout,
        open_timeout: @config.timeout
      ) do |http|
        http.request(req) do |res|
          handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

          res.read_body do |chunk|
            buffer << chunk

            while (newline_idx = buffer.index("\n"))
              line = buffer.slice!(0, newline_idx + 1).strip
              next if line.empty?

              # Tolerate SSE framing (e.g. "data: {...}") and ignore non-data lines.
              if line.start_with?("data:")
                line = line.sub(/\Adata:\s*/, "").strip
              elsif line.start_with?("event:") || line.start_with?(":")
                next
              end

              next if line.empty? || line == "[DONE]"

              obj = JSON.parse(line)

              # Expose the raw chunk to callers (presentation only).
              yield(obj) if block_given?

              msg = obj["message"]
              if msg.is_a?(Hash)
                delta_content = msg["content"]
                aggregated["message"]["content"] << delta_content.to_s if delta_content

                aggregated["message"]["tool_calls"] = msg["tool_calls"] if msg["tool_calls"]

                aggregated["message"]["role"] = msg["role"] if msg["role"]
              end

              # Many Ollama stream payloads include `done: true` on the last line.
              final_obj = obj if obj["done"] == true
            end
          end
        end
      end

      # Prefer returning the final "done: true" frame (it typically contains
      # useful metadata like durations), but always use our aggregated message
      # content/tool_calls since streaming payloads often send deltas.
      if final_obj.is_a?(Hash)
        combined = final_obj.dup
        combined_message =
          if combined["message"].is_a?(Hash)
            combined["message"].dup
          else
            {}
          end

        agg_message = aggregated["message"] || {}

        agg_content = agg_message["content"].to_s
        combined_message["content"] = agg_content unless agg_content.empty?

        combined_message["tool_calls"] = agg_message["tool_calls"] if agg_message.key?("tool_calls")
        combined_message["role"] ||= agg_message["role"] if agg_message["role"]

        combined["message"] = combined_message unless combined_message.empty?
        return combined
      end

      aggregated
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse streaming response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockLength
  end
  # rubocop:enable Metrics/ClassLength
end

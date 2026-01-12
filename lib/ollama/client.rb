# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "errors"
require_relative "schema_validator"
require_relative "config"

module Ollama
  # Main client class for interacting with Ollama API
  class Client
    def initialize(config: nil)
      @config = config || default_config
      @uri = URI("#{@config.base_url}/api/generate")
      @chat_uri = URI("#{@config.base_url}/api/chat")
      @base_uri = URI(@config.base_url)
    end

    # Chat API method matching JavaScript ollama.chat() interface
    # Supports structured outputs via format parameter
    #
    # @param model [String] Model name (overrides config.model)
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param format [Hash, nil] JSON Schema for structured outputs
    # @param options [Hash, nil] Additional options (temperature, top_p, etc.)
    # @return [Hash] Parsed and validated JSON response matching the format schema
    def chat(messages:, model: nil, format: nil, options: {}, strict: false, allow_chat: false, return_meta: false)
      unless allow_chat || strict
        raise Error,
              "chat() is intentionally gated because it is easy to misuse inside agents. " \
              "Prefer generate(). If you really want chat(), pass allow_chat: true (or strict: true)."
      end

      attempts = 0
      @current_schema = format # Store for validation
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        raw = call_chat_api(model: model, messages: messages, format: format, tools: nil, options: options)
        attempt_latency_ms = elapsed_ms(attempt_started_at)

        emit_response_hook(
          raw,
          {
            endpoint: "/api/chat",
            model: model || @config.model,
            attempt: attempts,
            attempt_latency_ms: attempt_latency_ms
          }
        )

        parsed = parse_json_response(raw)

        # CRITICAL: If format is provided, free-text output is forbidden
        if format
          raise SchemaViolationError, "Empty or nil response when format schema is required" if parsed.nil? || parsed.empty?
          SchemaValidator.validate!(parsed, format)
        end

        return parsed unless return_meta

        {
          "data" => parsed,
          "meta" => {
            "endpoint" => "/api/chat",
            "model" => (model || @config.model),
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
      rescue InvalidJSONError, SchemaViolationError => e
        raise e if strict
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      rescue TimeoutError, Error => e
        raise RetryExhaustedError, "Failed after #{attempts} attempts: #{e.message}" if attempts > @config.retries

        retry
      end
    end

    # Raw Chat API method that returns the full parsed response body.
    #
    # This is intended for advanced use cases such as tool-calling loops where
    # callers need access to fields like `message.tool_calls`.
    #
    # @param model [String] Model name (overrides config.model)
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param format [Hash, nil] JSON Schema for structured outputs (validates message.content JSON when present)
    # @param tools [Array<Hash>, nil] Tool definitions (OpenAI-style schema) sent to Ollama
    # @param options [Hash, nil] Additional options (temperature, top_p, etc.)
    # @return [Hash] Full parsed JSON response body from Ollama
    def chat_raw(messages:, model: nil, format: nil, tools: nil, options: {}, strict: false, allow_chat: false,
                 return_meta: false, stream: false, &on_chunk)
      unless allow_chat || strict
        raise Error,
              "chat_raw() is intentionally gated because it is easy to misuse inside agents. " \
              "Prefer generate(). If you really want chat_raw(), pass allow_chat: true (or strict: true)."
      end

      attempts = 0
      @current_schema = format # Store for validation
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        raw_body =
          if stream
            call_chat_api_raw_stream(
              model: model,
              messages: messages,
              format: format,
              tools: tools,
              options: options,
              &on_chunk
            )
          else
            call_chat_api_raw(model: model, messages: messages, format: format, tools: tools, options: options)
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
          raise SchemaViolationError, "Empty or nil response when format schema is required" if content.nil? || content.empty?

          parsed_content = parse_json_response(content)
          raise SchemaViolationError, "Empty or nil response when format schema is required" if parsed_content.nil? || parsed_content.empty?
          SchemaValidator.validate!(parsed_content, format)
        end

        return parsed_body unless return_meta

        {
          "data" => parsed_body,
          "meta" => {
            "endpoint" => "/api/chat",
            "model" => (model || @config.model),
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

    def generate(prompt:, schema:, strict: false, return_meta: false)
      attempts = 0
      @current_schema = schema # Store for prompt enhancement
      started_at = monotonic_time

      begin
        attempts += 1
        attempt_started_at = monotonic_time
        raw = call_api(prompt)
        attempt_latency_ms = elapsed_ms(attempt_started_at)

        emit_response_hook(
          raw,
          {
            endpoint: "/api/generate",
            model: @config.model,
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
            "model" => @config.model,
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

    def generate_strict!(prompt:, schema:, return_meta: false)
      generate(prompt: prompt, schema: schema, strict: true, return_meta: return_meta)
    end

    # Lightweight server health check.
    # Returns true/false by default; pass return_meta: true for details.
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
            unless expected == ch
              raise InvalidJSONError, "Malformed JSON in response. Response: #{text[start_idx, 200]}..."
            end
            return text[start_idx..i] if stack.empty?
          end
        end

        i += 1
      end

      raise InvalidJSONError, "Incomplete JSON in response. Response: #{text[start_idx, 200]}..."
    end

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

      unless res.is_a?(Net::HTTPSuccess)
        status_code = res.code.to_i
        requested_model = model || @config.model

        case status_code
        when 404
          raise NotFoundError.new(res.message, requested_model: requested_model)
        when 400, 401, 403
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        when 408, 429, 500, 503
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        else
          raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
        end
      end

      res.body
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end

    def call_chat_api_raw_stream(model:, messages:, format:, tools:, options:)
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
          "content" => ""
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
          unless res.is_a?(Net::HTTPSuccess)
            status_code = res.code.to_i
            requested_model = model || @config.model

            case status_code
            when 404
              raise NotFoundError.new(res.message, requested_model: requested_model)
            when 400, 401, 403
              raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
            when 408, 429, 500, 503
              raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
            else
              raise HTTPError.new("HTTP #{res.code}: #{res.message}", status_code)
            end
          end

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

                if msg["tool_calls"]
                  aggregated["message"]["tool_calls"] = msg["tool_calls"]
                end

                aggregated["message"]["role"] = msg["role"] if msg["role"]
              end

              # Many Ollama stream payloads include `done: true` on the last line.
              if obj["done"] == true
                final_obj = obj
              end
            end
          end
        end
      end

      # If we saw a final object, prefer it when it already contains a complete message.
      if final_obj.is_a?(Hash) && final_obj["message"].is_a?(Hash)
        # If the final message content is empty, fall back to our aggregation.
        if final_obj.dig("message", "content").to_s.empty? && !aggregated.dig("message", "content").to_s.empty?
          final_obj["message"]["content"] = aggregated["message"]["content"]
        end
        if final_obj.dig("message", "tool_calls").nil? && aggregated.dig("message", "tool_calls")
          final_obj["message"]["tool_calls"] = aggregated["message"]["tool_calls"]
        end
        return final_obj
      end

      aggregated
    rescue JSON::ParserError => e
      raise InvalidJSONError, "Failed to parse streaming response: #{e.message}"
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise TimeoutError, "Request timed out after #{@config.timeout}s"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
      raise Error, "Connection failed: #{e.message}"
    end
  end
end

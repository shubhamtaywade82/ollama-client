# frozen_string_literal: true

require_relative "chat_stream_processor"
require_relative "../responses/chat"
require_relative "../serializers/chat"
require_relative "../parsers/chat"
require_relative "chat/request_preparer"
require_relative "../chat"
require_relative "../schema_validator"
require_relative "../json_fragment_extractor"

module Ollama
  class Client
    # Chat completion endpoint — the primary method for multi-turn conversations
    module Chat
      UNDEFINED = Object.new.freeze
      private_constant :UNDEFINED

      # @param messages [Array<Hash>, nil] Chat history (returns stateful Ollama::Chat if omitted)
      # @param model [String, nil] Model name override
      # @param format [Hash, String, nil] "json" or JSON Schema object for structured output
      # @param tools [Array<Hash>, nil] Function tools the model may call
      # @param stream [Boolean, nil] Stream partial responses (default: determined by hooks)
      # @param think [Boolean, String, nil] Enable thinking output (true/false/"high"/"medium"/"low")
      # @param keep_alive [String, nil] Model keep-alive duration (e.g. "5m", "0")
      # @param options [Hash, nil] Runtime options (temperature, top_p, num_ctx, etc.)
      # @param logprobs [Boolean, nil] Return log probabilities
      # @param top_logprobs [Integer, nil] Number of top logprobs to return
      # @param profile [:auto, false, ModelProfile] Capability profile for model-aware behavior
      # @param inputs [Array<Hash>, nil] Typed multimodal inputs (overrides last user message)
      # @param strict [Boolean, nil] Enable strict JSON validation and auto-repair retry
      # @param hooks [Hash] Streaming callbacks
      # @return [Ollama::Response, Ollama::Chat]
      # rubocop:disable Metrics/ParameterLists
      def chat(messages: UNDEFINED, model: nil, format: nil, tools: nil, stream: nil,
               think: nil, keep_alive: nil, options: nil, logprobs: nil,
               top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil, strict: nil)
        # rubocop:enable Metrics/ParameterLists
        if messages.equal?(UNDEFINED)
          return Ollama::Chat.new(self, model: model, tools: tools, format: format,
                                        think: think, keep_alive: keep_alive,
                                        options: options, profile: profile)
        end

        raise ArgumentError, "messages is required" if messages.nil? || messages.empty?

        params = Params::Chat.new(
          messages: messages, model: model, format: format, tools: tools,
          stream: stream, think: think, keep_alive: keep_alive, options: options,
          logprobs: logprobs, top_logprobs: top_logprobs, hooks: hooks,
          profile: profile, inputs: inputs, strict: strict
        )
        chat_with_params(params)
      end

      # @param params [Ollama::Params::Chat] Chat parameters
      # @return [Ollama::Response] Response wrapper with message, tool_calls, timing, etc.
      def chat_with_params(params)
        raise ArgumentError, "messages is required" if params.messages.nil? || params.messages.empty?

        return execute_chat_with_repair(params) if params.strict && params.format

        dispatch_chat_request(params)
      end

      private

      def execute_chat_with_repair(params)
        attempts = 0
        max_attempts = @config.retries + 1
        current_messages = params.messages.map(&:dup)

        loop do
          attempts += 1
          turn_params = params.dup
          turn_params.messages = current_messages
          turn_params.strict = false
          response = dispatch_chat_request(turn_params)

          validate_chat_schema!(response.content, params.format)
          return response
        rescue SchemaViolationError, InvalidJSONError => e
          raise e if attempts >= max_attempts

          repair_msg = "CRITICAL FIX: Your last response was invalid or violated the schema. " \
                       "Error: #{e.message}. Return ONLY valid JSON."
          current_messages << { role: "assistant", content: response&.content.to_s }
          current_messages << { role: "user", content: repair_msg }
        end
      end

      def validate_chat_schema!(content, schema)
        return unless content && schema

        json_str = JsonFragmentExtractor.call(content)
        parsed = JSON.parse(json_str)
        SchemaValidator.validate!(parsed, schema) if schema.is_a?(Hash)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse JSON response: #{e.message}"
      end

      def dispatch_chat_request(params)
        request = RequestPreparer.new(config: @config, provider: @provider).build_request(params, self)
        transport_req = Serializers::Chat.new.call(request)
        response_data = execute_chat_transport(transport_req, request, params)

        emit_response_hook(response_data.is_a?(Hash) ? response_data.to_json : response_data,
                           endpoint: request.metadata[:uri].path, model: request.model)

        Responses::Chat.new(response_data)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse chat response: #{e.message}"
      end

      def execute_chat_transport(transport_req, request, params)
        with_rate_limit_key_rotation do |api_key|
          @config.apply_auth_to(transport_req, api_key: api_key) if transport_req.is_a?(Transport::Request)

          if request.stream
            drain_stream_response(transport_req, params.hooks)
          else
            execute_unary_response(transport_req, request.model)
          end
        end
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        params.hooks[:on_error]&.call(e)
        raise TimeoutError, "Request timed out after #{request.metadata[:timeout]}s"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        params.hooks[:on_error]&.call(e)
        raise Error, "Connection failed: #{e.message}"
      rescue Error => e
        params.hooks[:on_error]&.call(e)
        raise e
      end

      def drain_stream_response(transport_req, hooks)
        buffer = +""
        processor = ChatStreamProcessor.new(hooks, provider: @provider)
        processor.send(:reset_accumulators!)

        @pipeline.stream(transport_req) do |chunk|
          processor.send(:drain_chunk, buffer, chunk)
        end

        processor.send(:build_result)
      end

      def execute_unary_response(transport_req, target_model)
        res = @pipeline.call(transport_req)
        handle_http_error(res.raw, requested_model: target_model) if res.raw && !res.raw.is_a?(Net::HTTPSuccess)

        Parsers::Chat.new(provider: @provider).call(res).to_h
      end
    end
  end
end

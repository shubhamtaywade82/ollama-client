# frozen_string_literal: true

require_relative "chat_stream_processor"
require_relative "../responses/chat"
require_relative "../serializers/chat"
require_relative "../parsers/chat"
require_relative "chat/request_preparer"

module Ollama
  class Client
    # Chat completion endpoint — the primary method for multi-turn conversations
    module Chat
      # @param messages [Array<Hash>] Chat history, each with :role and :content (required)
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
      # @param hooks [Hash] Streaming callbacks:
      #   :on_token    ->(text, logprobs=nil)   — final-answer token
      #   :on_thought  ->(text)                 — reasoning/thinking token
      #   :on_tool_call ->(tool_call_hash)      — tool call ready
      #   :on_error    ->(error)                — stream or connection error
      #   :on_complete ->                       — stream finished
      # @return [Ollama::Response] Response wrapper with message, tool_calls, timing, etc.
      # rubocop:disable Metrics/ParameterLists
      def chat(messages:, model: nil, format: nil, tools: nil, stream: nil,
               think: nil, keep_alive: nil, options: nil, logprobs: nil,
               top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil)
        # rubocop:enable Metrics/ParameterLists
        params = Params::Chat.new(
          messages: messages, model: model, format: format, tools: tools,
          stream: stream, think: think, keep_alive: keep_alive, options: options,
          logprobs: logprobs, top_logprobs: top_logprobs, hooks: hooks,
          profile: profile, inputs: inputs
        )
        chat_with_params(params)
      end

      # @param params [Ollama::Params::Chat] Chat parameters
      # @return [Ollama::Response] Response wrapper with message, tool_calls, timing, etc.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def chat_with_params(params)
        raise ArgumentError, "messages is required" if params.messages.nil? || params.messages.empty?

        preparer = RequestPreparer.new(config: @config, provider: @provider)
        request = preparer.build_request(params, self)

        serializer = Serializers::Chat.new
        transport_req = serializer.call(request)
        response_data = nil
        stream_enabled = request.stream
        config_timeout = request.metadata[:timeout]
        target_model = request.model
        chat_uri = request.metadata[:uri]

        begin
          with_rate_limit_key_rotation do |api_key|
            response_data = nil
            @config.apply_auth_to(transport_req, api_key: api_key) if transport_req.is_a?(Transport::Request)

            if stream_enabled
              buffer = +""
              processor = ChatStreamProcessor.new(params.hooks, provider: @provider)
              processor.send(:reset_accumulators!)

              @pipeline.stream(transport_req) do |chunk|
                processor.send(:drain_chunk, buffer, chunk)
              end

              response_data = processor.send(:build_result)
            else
              transport_response = @pipeline.call(transport_req)
              if transport_response.raw && !transport_response.raw.is_a?(Net::HTTPSuccess)
                handle_http_error(transport_response.raw,
                                  requested_model: target_model)
              end

              parser = Parsers::Chat.new(provider: @provider)
              parsed_response = parser.call(transport_response)
              response_data = parsed_response.to_h
            end
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          params.hooks[:on_error]&.call(e)
          raise TimeoutError, "Request timed out after #{config_timeout}s"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          params.hooks[:on_error]&.call(e)
          raise Error, "Connection failed: #{e.message}"
        rescue Error => e
          params.hooks[:on_error]&.call(e)
          raise e
        end

        emit_response_hook(response_data.is_a?(Hash) ? response_data.to_json : response_data,
                           endpoint: chat_uri.path, model: target_model)

        Responses::Chat.new(response_data)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse chat response: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end

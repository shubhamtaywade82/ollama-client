# frozen_string_literal: true

require_relative "chat_stream_processor"

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
      def chat(messages:, model: nil, format: nil, tools: nil, stream: nil,
               think: nil, keep_alive: nil, options: nil, logprobs: nil,
               top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil)
        params = Params::Chat.new(
          messages: messages, model: model, format: format, tools: tools,
          stream: stream, think: think, keep_alive: keep_alive, options: options,
          logprobs: logprobs, top_logprobs: top_logprobs, hooks: hooks,
          profile: profile, inputs: inputs
        )
        chat_with_params(params)
      end

      # @param params [Ollama::Params::Chat] Chat parameters
      # @return [Ollama::Response]
      def chat_with_params(params)
        raise ArgumentError, "messages is required" if params.messages.nil? || params.messages.empty?

        target_model = params.model || @config.model
        active_profile = resolve_profile(target_model, params.profile)
        adapter = PromptAdapters.for(active_profile) if active_profile

        # Apply multimodal inputs: build typed message and append to history
        messages = apply_inputs(params.messages, params.inputs, active_profile) if params.inputs

        # Apply prompt adapter (e.g. Gemma 4 prepends the family think tag to the system prompt)
        adapted_messages = adapter ? adapter.adapt_messages(messages, think: !params.think.nil?, tools: params.tools) : messages

        # Resolve think flag: adapter may handle it via prompt tag instead of API flag
        effective_think = resolve_think_flag(params.think, adapter)

        chat_uri = @provider.chat_endpoint
        req = Net::HTTP::Post.new(chat_uri)
        req["Content-Type"] = "application/json"

        stream_enabled = params.stream.nil? ? hooks_present?(params.hooks) : params.stream

        request_params = { model: target_model, messages: adapted_messages, stream: stream_enabled }
        request_params[:format]      = params.format if params.format
        request_params[:tools]       = params.tools if params.tools
        request_params[:think]       = effective_think unless effective_think.nil?
        request_params[:keep_alive]  = params.keep_alive if params.keep_alive
        request_params[:logprobs]    = params.logprobs unless params.logprobs.nil?
        request_params[:top_logprobs] = params.top_logprobs if params.top_logprobs
        request_params[:options] = build_options_with_profile(params.options, active_profile)

        req.body = @provider.format_chat_request(request_params).to_json
        @config.apply_auth_to(req)
        response_data = nil

        begin
          Net::HTTP.start(chat_uri.hostname, chat_uri.port,
                          **@config.http_connection_options(chat_uri)) do |h|
            h.request(req) do |res|
              handle_http_error(res, requested_model: target_model) unless res.is_a?(Net::HTTPSuccess)

              response_data = if stream_enabled
                                ChatStreamProcessor.call(res, params.hooks, provider: @provider)
                              else
                                @provider.normalize_chat_response(JSON.parse(res.body))
                              end
            end
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          params.hooks[:on_error]&.call(e)
          raise TimeoutError, "Request timed out after #{@config.timeout}s"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          params.hooks[:on_error]&.call(e)
          raise Error, "Connection failed: #{e.message}"
        rescue Error => e
          params.hooks[:on_error]&.call(e)
          raise e
        end

        emit_response_hook(response_data.is_a?(Hash) ? response_data.to_json : response_data,
                           endpoint: chat_uri.path, model: target_model)

        Response.new(response_data)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse chat response: #{e.message}"
      end

      private

      def hooks_present?(hooks)
        [hooks[:on_token], hooks[:on_thought], hooks[:on_error],
         hooks[:on_complete], hooks[:on_tool_call]].any?
      end

      def apply_inputs(messages, inputs, active_profile)
        input_obj = MultimodalInput.build(inputs, profile: active_profile || ModelProfile.for("generic"))
        messages + [input_obj.to_message]
      end

      # Gemma 4 uses the system-prompt tag — do not send think: true to the API.
      # Other adapters that inject_think_flag? pass the user's think value through.
      def resolve_think_flag(think, adapter)
        return nil if think.nil?
        return nil if adapter&.inject_think_flag? == false && adapter.is_a?(PromptAdapters::Gemma4)

        think
      end
    end
  end
end
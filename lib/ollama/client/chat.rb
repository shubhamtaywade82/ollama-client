# frozen_string_literal: true

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
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/AbcSize
      def chat(messages:, model: nil, format: nil, tools: nil, stream: nil,
               think: nil, keep_alive: nil, options: nil, logprobs: nil,
               top_logprobs: nil, hooks: {}, profile: :auto, inputs: nil)
        raise ArgumentError, "messages is required" if messages.nil? || messages.empty?

        target_model = model || @config.model
        active_profile = resolve_profile(target_model, profile)
        adapter = PromptAdapters.for(active_profile) if active_profile

        # Apply multimodal inputs: build typed message and append to history
        messages = apply_inputs(messages, inputs, active_profile) if inputs

        # Apply prompt adapter (e.g. Gemma 4 injects <|think|> into system prompt)
        adapted_messages = adapter ? adapter.adapt_messages(messages, think: !!think) : messages

        # Resolve think flag: adapter may handle it via prompt tag instead of API flag
        effective_think = resolve_think_flag(think, adapter)

        chat_uri = URI("#{@config.base_url}/api/chat")
        req = Net::HTTP::Post.new(chat_uri)
        req["Content-Type"] = "application/json"

        stream_enabled = stream.nil? ? hooks_present?(hooks) : stream

        body = { model: target_model, messages: adapted_messages, stream: stream_enabled }
        body[:format]      = format if format
        body[:tools]       = tools if tools
        body[:think]       = effective_think unless effective_think.nil?
        body[:keep_alive]  = keep_alive if keep_alive
        body[:logprobs]    = logprobs unless logprobs.nil?
        body[:top_logprobs] = top_logprobs if top_logprobs
        body[:options]     = build_options_with_profile(options, active_profile)

        req.body = body.to_json
        @config.apply_auth_to(req)
        response_data = nil

        begin
          Net::HTTP.start(chat_uri.hostname, chat_uri.port,
                          **@config.http_connection_options(chat_uri)) do |h|
            h.request(req) do |res|
              handle_http_error(res, requested_model: target_model) unless res.is_a?(Net::HTTPSuccess)

              response_data = stream_enabled ? handle_chat_stream(res, hooks) : JSON.parse(res.body)
            end
          end
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          hooks[:on_error]&.call(e)
          raise TimeoutError, "Request timed out after #{@config.timeout}s"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          hooks[:on_error]&.call(e)
          raise Error, "Connection failed: #{e.message}"
        rescue Error => e
          hooks[:on_error]&.call(e)
          raise e
        end

        emit_response_hook(response_data.is_a?(Hash) ? response_data.to_json : response_data,
                           endpoint: "/api/chat", model: target_model)

        Response.new(response_data)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse chat response: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/AbcSize

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

      # Handle NDJSON streaming for chat endpoint
      def handle_chat_stream(res, hooks)
        full_content  = +""
        full_thinking = +""
        full_logprobs = []
        last_data = nil
        thinking_started = false

        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          while (newline_idx = buffer.index("\n"))
            line = buffer.slice!(0, newline_idx + 1).strip
            next if line.empty?

            begin
              obj = JSON.parse(line)
              thinking_started, last_data = process_chat_stream_chunk(
                obj, hooks, full_content, full_thinking, full_logprobs, last_data, thinking_started
              )
            rescue JSON::ParserError
              # Ignore malformed stream chunks
            end
          end
        end

        result = last_data || {}
        result["message"] ||= {}
        result["message"]["content"] = full_content
        result["message"]["thinking"] = full_thinking unless full_thinking.empty?
        result["message"]["role"] ||= "assistant"
        result["logprobs"] = full_logprobs unless full_logprobs.empty?
        result
      end

      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/ParameterLists
      def process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data, thinking_started)
        if obj["error"]
          error = StreamError.new(obj["error"])
          hooks[:on_error]&.call(error)
          raise error
        end

        if obj["message"]
          content = obj["message"]["content"]
          thinking = obj["message"]["thinking"]

          # Emit thinking events when reasoning content arrives
          if thinking && !thinking.empty?
            unless thinking_started
              hooks[:on_thought]&.call(StreamEvent.new(type: :thought_start, data: nil))
              thinking_started = true
            end
            full_thinking << thinking
            hooks[:on_thought]&.call(StreamEvent.new(type: :thought_delta, data: thinking))
          end

          # Emit answer tokens
          if content && !content.empty?
            if thinking_started && !full_thinking.empty?
              hooks[:on_thought]&.call(StreamEvent.new(type: :thought_end, data: nil))
              thinking_started = false
            end
            full_content << content
            if hooks[:on_token]&.arity == 2
              hooks[:on_token].call(content, obj["logprobs"])
            else
              hooks[:on_token]&.call(content)
            end
          end

          full_logprobs.concat(obj["logprobs"]) if obj["logprobs"]
        end

        if obj["done"]
          # Emit tool call events from the final chunk
          tool_calls = obj.dig("message", "tool_calls")
          if tool_calls && !tool_calls.empty?
            tool_calls.each do |tc|
              hooks[:on_tool_call]&.call(tc)
            end
          end

          hooks[:on_complete]&.call
          return [thinking_started, obj]
        end

        [thinking_started, last_data]
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/ParameterLists
    end
  end
end

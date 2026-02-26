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
      # @param hooks [Hash] Streaming callbacks (:on_token, :on_error, :on_complete)
      # @return [Ollama::Response] Response wrapper with message, tool_calls, timing, etc.
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/AbcSize
      def chat(messages:, model: nil, format: nil, tools: nil, stream: nil,
               think: nil, keep_alive: nil, options: nil, logprobs: nil,
               top_logprobs: nil, hooks: {})
        raise ArgumentError, "messages is required" if messages.nil? || messages.empty?

        chat_uri = URI("#{@config.base_url}/api/chat")
        req = Net::HTTP::Post.new(chat_uri)
        req["Content-Type"] = "application/json"

        stream_enabled = stream.nil? ? !(hooks[:on_token] || hooks[:on_error] || hooks[:on_complete]).nil? : stream

        body = { model: model || @config.model, messages: messages, stream: stream_enabled }
        body[:format] = format if format
        body[:tools] = tools if tools
        body[:think] = think unless think.nil?
        body[:keep_alive] = keep_alive if keep_alive
        body[:logprobs] = logprobs unless logprobs.nil?
        body[:top_logprobs] = top_logprobs if top_logprobs
        body[:options] = build_options(options)

        req.body = body.to_json

        response_data = nil

        begin
          Net::HTTP.start(chat_uri.hostname, chat_uri.port,
                          read_timeout: @config.timeout, open_timeout: @config.timeout) do |h|
            h.request(req) do |res|
              handle_http_error(res, requested_model: model || @config.model) unless res.is_a?(Net::HTTPSuccess)

              response_data = stream_enabled ? handle_chat_stream(res, hooks) : JSON.parse(res.body)
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

        Response.new(response_data)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse chat response: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Metrics/AbcSize

      private

      # Handle NDJSON streaming for chat endpoint
      def handle_chat_stream(res, hooks)
        full_content = +""
        full_thinking = +""
        full_logprobs = []
        last_data = nil

        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          while (newline_idx = buffer.index("\n"))
            line = buffer.slice!(0, newline_idx + 1).strip
            next if line.empty?

            begin
              obj = JSON.parse(line)
              last_data = process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data)
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

      def process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data)
        if obj["error"]
          error = StreamError.new(obj["error"])
          hooks[:on_error]&.call(error)
          raise error
        end

        if obj["message"]
          content = obj["message"]["content"]
          thinking = obj["message"]["thinking"]

          if content && !content.empty?
            full_content << content
            if hooks[:on_token]&.arity == 2
              hooks[:on_token].call(content, obj["logprobs"])
            else
              hooks[:on_token]&.call(content)
            end
          end

          full_thinking << thinking if thinking && !thinking.empty?
          full_logprobs.concat(obj["logprobs"]) if obj["logprobs"]
        end

        if obj["done"]
          hooks[:on_complete]&.call
          return obj
        end

        last_data
      end
    end
  end
end

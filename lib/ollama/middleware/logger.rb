# frozen_string_literal: true

require_relative "../middleware"

module Ollama
  class Middleware
    # Logger middleware - logs request/response information
    class Logger < Ollama::Middleware
      attr_reader :logger, :level, :formatter

      def initialize(logger: nil, level: :info, formatter: nil)
        super()
        @logger = logger || default_logger
        @level = level
        @formatter = formatter || method(:default_format)
      end

      def before_request(request, _env)
        log(:info, "→ Request", {
              endpoint: request.endpoint,
              model: request.model,
              streaming: request.streaming?,
              metadata: request.metadata
            })
        request
      end

      def after_response(response, env)
        duration = env[:duration_ms]
        log(:info, "← Response", {
              endpoint: env[:request]&.endpoint,
              status: response.status,
              duration_ms: duration,
              cached: env[:cache_hit] || false
            })
        response
      end

      def on_error(error, env)
        log(:error, "✗ Error", {
              endpoint: env[:request]&.endpoint,
              error: error.class.name,
              message: error.message
            })
        nil
      end

      def on_stream_chunk(chunk, env)
        log(:debug, "∼ Stream", {
              endpoint: env[:request]&.endpoint,
              chunk_size: chunk.to_s.bytesize
            })
      end

      private

      def default_logger
        require "logger"
        ::Logger.new($stdout).tap { |l| l.level = ::Logger::INFO }
      end

      def default_format(event, payload)
        "[#{Time.now.iso8601}] #{event}: #{payload.inspect}"
      end

      def log(level, event, payload)
        return unless @logger.respond_to?(level)

        message = @formatter.call(event, payload)
        @logger.send(level, message)
      end
    end
  end
end

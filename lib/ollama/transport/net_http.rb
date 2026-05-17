# frozen_string_literal: true

module Ollama
  module Transport
    class NetHTTP < Base
      def request(uri:, request:, read_timeout:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw_response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          **@config.http_connection_options(uri, read_timeout: read_timeout)
        ) { |http| http.request(request) }
        ended = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Response.new(
          status: raw_response.code,
          headers: raw_response.to_hash,
          body: raw_response.body,
          raw: raw_response,
          duration_ms: ((ended - started) * 1000.0).round(2)
        )
      end

      def stream(_uri:, _request:, &_block)
        raise NotImplementedError, "NetHTTP stream adapter not implemented yet"
      end

      def capabilities
        [:request]
      end
    end
  end
end

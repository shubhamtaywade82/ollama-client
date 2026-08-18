# frozen_string_literal: true

module Ollama
  module Transport
    # Net::HTTP-backed transport adapter.
    class NetHTTP < Base
      def request(uri:, request:, read_timeout:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        req = build_raw_request(request)
        raw_response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          **@config.http_connection_options(uri, read_timeout: read_timeout)
        ) { |http| http.request(req) }
        ended = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Response.new(
          status: raw_response.code,
          headers: raw_response.to_hash,
          body: raw_response.body,
          raw: raw_response,
          duration_ms: ((ended - started) * 1000.0).round(2)
        )
      end

      def stream(uri:, request:, read_timeout: nil, &block)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw_response = nil
        req = build_raw_request(request)
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          **@config.http_connection_options(uri, read_timeout: read_timeout)
        ) do |http|
          http.request(req) do |res|
            raw_response = res
            raise HTTPError, res unless res.is_a?(Net::HTTPSuccess)

            res.read_body(&block)
          end
        end
        ended = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Response.new(
          status: raw_response.code,
          headers: raw_response.to_hash,
          body: nil,
          raw: raw_response,
          duration_ms: ((ended - started) * 1000.0).round(2)
        )
      end

      def capabilities
        %i[request stream]
      end

      private

      def build_raw_request(request)
        return request unless request.is_a?(Transport::Request)

        klass = case request.method
                when :get  then Net::HTTP::Get
                when :post then Net::HTTP::Post
                when :delete then Net::HTTP::Delete
                else raise ArgumentError, "Unsupported method: #{request.method}"
                end

        req = klass.new(request.uri)
        request.headers.each { |k, v| req[k] = v }
        req.body = request.body if request.body
        req
      end
    end
  end
end

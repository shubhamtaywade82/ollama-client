# frozen_string_literal: true

module Ollama
  class Client
    # Raw transport escape hatch for unsupported or experimental endpoints.
    module Raw
      def raw
        @raw ||= RawAdapter.new(self)
      end

      class RawAdapter
        def initialize(client)
          @client = client
          @config = client.instance_variable_get(:@config)
        end

        def get(path, query: nil)
          request(:get, path, payload: nil, query: query)
        end

        def post(path, payload: {}, query: nil)
          request(:post, path, payload: payload, query: query)
        end

        def delete(path, payload: nil, query: nil)
          request(:delete, path, payload: payload, query: query)
        end

        private

        def request(method, path, payload:, query: nil)
          uri = URI.join(@config.base_url, path)
          uri.query = URI.encode_www_form(query) if query&.any?

          req = build_request(method, uri, payload)
          res = @client.send(:http_request, uri, req)
          @client.send(:handle_http_error, res) unless res.is_a?(Net::HTTPSuccess)

          parse_body(res)
        end

        def build_request(method, uri, payload)
          req = case method
                when :get then Net::HTTP::Get.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                when :delete then Net::HTTP::Delete.new(uri)
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end
          req["Content-Type"] = "application/json"
          req.body = payload.to_json unless payload.nil?
          req
        end

        def parse_body(res)
          return {} if res.body.nil? || res.body.empty?

          JSON.parse(res.body)
        rescue JSON::ParserError
          { "raw" => res.body }
        end
      end
    end
  end
end

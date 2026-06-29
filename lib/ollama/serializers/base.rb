# frozen_string_literal: true

module Ollama
  module Serializers
    # Base serializer contract - converts Request to Transport::Request
    class Base
      def call(request)
        raise NotImplementedError, "serializer must implement #call"
      end

      protected

      # Build the JSON body from request attributes
      def build_body(_request)
        {}
      end

      # Build headers for the request
      def build_headers(_request)
        { "Content-Type" => "application/json" }
      end

      # Build query parameters
      def build_query(_request)
        {}
      end

      # Determine HTTP method
      def http_method(_request)
        :post
      end

      # Get path from request
      def path(request)
        request.base_path
      end

      # Construct full URI from base URL and endpoint path
      def build_uri(request, base_path)
        request.metadata[:uri] || URI.join(request.metadata[:base_url] || "http://localhost:11434", base_path)
      end
    end
  end
end

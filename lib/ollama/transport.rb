# frozen_string_literal: true

require "json"
require_relative "transport/base"
require_relative "transport/net_http"
require_relative "transport/response"
require_relative "transport/mock"

module Ollama
  # Transport adapter namespace and factory.
  module Transport
    def self.build(config)
      adapter = config.respond_to?(:transport_adapter) ? config.transport_adapter : :net_http

      case adapter
      when :net_http, nil
        NetHTTP.new(config)
      when :mock
        Mock.new(config)
      else
        raise ArgumentError, "Unsupported transport adapter: #{adapter.inspect}"
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require_relative "api_key_pool"

module Ollama
  # Configuration class with safe defaults for agent-grade usage
  #
  # ⚠️ THREAD SAFETY WARNING:
  # Global configuration access is mutex-protected, but modifying global config
  # while clients are active can cause race conditions. For concurrent agents
  # or multi-threaded applications, use per-client configuration (recommended):
  #
  #   config = Ollama::Config.new
  #   config.model = "llama3.1"
  #   client = Ollama::Client.new(config: config)
  #
  # Each client instance with its own config is thread-safe.
  #
  class Config
    attr_accessor :base_url, :model, :timeout, :retries, :temperature,
                  :top_p, :num_ctx, :on_response, :strict_json,
                  :transport_adapter, :provider
    attr_reader :api_key, :api_keys, :enable_multi_key_concurrency, :api_key_pool

    def initialize
      @base_url = "http://localhost:11434"
      @model = "llama3.2:3b"
      @timeout = 30
      @retries = 2
      @strict_json = true
      @temperature = 0.2
      @top_p = 0.9
      @num_ctx = 8192
      @on_response = nil
      @enable_multi_key_concurrency = self.class.truthy_env?(ENV.fetch("ENABLE_MULTI_KEY_CONCURRENCY", nil))
      @api_key = nil
      @api_keys = []
      @api_key_pool = ApiKeyPool.new([], concurrency_enabled: @enable_multi_key_concurrency)
      self.api_keys = self.class.env_api_keys
      @transport_adapter = :net_http
      @provider = :ollama
    end

    # Set Authorization header on a request when api_key is configured (e.g. for Ollama Cloud).
    # No-op when api_key is nil or empty.
    #
    # @param req [Net::HTTP::Request]
    def apply_auth_to(req, api_key: self.api_key)
      if api_key.to_s.strip.empty?
        req.delete("Authorization")
      else
        req["Authorization"] = "Bearer #{api_key}"
      end
    end

    # Set a single API key and rebuild the immutable key pool.
    #
    # @param value [String, nil]
    def api_key=(value)
      @api_key = value
      rebuild_api_key_pool([value])
    end

    # Set multiple API keys and rebuild the immutable key pool.
    #
    # @param values [Array<String>, String, nil]
    def api_keys=(values)
      keys = self.class.parse_api_keys(values)
      @api_key = keys.first
      rebuild_api_key_pool(keys)
    end

    # Enable or disable thread-safe round-robin key distribution for new requests.
    #
    # @param value [Boolean]
    def enable_multi_key_concurrency=(value)
      @enable_multi_key_concurrency = value ? true : false
      rebuild_api_key_pool(@api_keys)
    end

    # Net::HTTP connection options built from current config and target URI.
    #
    # @param uri [URI]
    # @param read_timeout [Integer]
    # @return [Hash] options suitable for Net::HTTP.start
    def http_connection_options(uri, read_timeout: timeout)
      {
        use_ssl: uri.scheme == "https",
        read_timeout: read_timeout,
        open_timeout: timeout
      }
    end

    def inspect
      attributes = {
        base_url: base_url.inspect,
        model: model.inspect,
        provider: provider.inspect,
        timeout: timeout,
        retries: retries,
        strict_json: strict_json,
        temperature: temperature,
        top_p: top_p,
        num_ctx: num_ctx,
        api_key: "(redacted)",
        api_keys: "(#{api_keys.size} configured)",
        enable_multi_key_concurrency: enable_multi_key_concurrency,
        transport_adapter: transport_adapter.inspect
      }

      "#<#{self.class.name} #{attributes.map { |k, v| "#{k}=#{v}" }.join(" ")}>"
    end

    # Load configuration from JSON file (useful for production deployments)
    #
    # @param path [String] Path to JSON config file
    # @return [Config] New Config instance
    #
    # The caller is responsible for ensuring the config path is trusted.
    # Do not pass unvalidated user input directly to this method.
    #
    # Example JSON:
    #   {
    #     "base_url": "http://localhost:11434",
    #     "api_key": "optional-for-ollama-cloud",
    #     "model": "llama3.2:3b",
    #     "provider": "ollama",
    #     "timeout": 30,
    #     "retries": 3,
    #     "temperature": 0.2,
    #     "top_p": 0.9,
    #     "num_ctx": 8192
    #   }
    def self.load_from_json(path)
      data = JSON.parse(File.read(path))
      new.tap { |config| map_json_data(config, data) }
    rescue JSON::ParserError => e
      raise Error, "Failed to parse config JSON: #{e.message}"
    rescue Errno::ENOENT
      raise Error, "Config file not found: #{path}"
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.map_json_data(config, data)
      config.base_url = data["base_url"] if data.key?("base_url")
      config.api_keys = data["api_keys"] if data.key?("api_keys")
      config.api_key = data["api_key"] if data.key?("api_key")
      config.enable_multi_key_concurrency = data["enable_multi_key_concurrency"] if data.key?("enable_multi_key_concurrency")
      config.model = data["model"] if data.key?("model")
      config.provider = data["provider"]&.to_sym if data.key?("provider")
      config.timeout = data["timeout"] if data.key?("timeout")
      config.retries = data["retries"] if data.key?("retries")
      config.strict_json = data["strict_json"] if data.key?("strict_json")
      config.temperature = data["temperature"] if data.key?("temperature")
      config.top_p = data["top_p"] if data.key?("top_p")
      config.num_ctx = data["num_ctx"] if data.key?("num_ctx")
      config.transport_adapter = data["transport_adapter"]&.to_sym if data.key?("transport_adapter")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    private_class_method :map_json_data

    # Parse a comma-separated String or Array of API keys into a frozen key list.
    #
    # @param value [String, Array<String>, nil]
    # @return [Array<String>] frozen key list
    def self.parse_api_keys(value)
      Array(value).flat_map { |item| item.to_s.split(",") }
                  .map(&:strip)
                  .reject(&:empty?)
                  .freeze
    end

    # Resolve API keys from OLLAMA_API_KEYS with OLLAMA_API_KEY fallback.
    #
    # @return [Array<String>] frozen key list
    def self.env_api_keys
      keys = parse_api_keys(ENV.fetch("OLLAMA_API_KEYS", nil))
      return keys unless keys.empty?

      parse_api_keys(ENV.fetch("OLLAMA_API_KEY", nil))
    end

    # @param value [String, nil]
    # @return [Boolean]
    def self.truthy_env?(value)
      %w[1 true yes y on].include?(value.to_s.strip.downcase)
    end

    def initialize_copy(source)
      super
      @api_keys = source.api_keys.dup.freeze
      @api_key = @api_keys.first
      rebuild_api_key_pool(@api_keys)
    end

    private

    def rebuild_api_key_pool(keys)
      @api_keys = self.class.parse_api_keys(keys)
      @api_key = @api_keys.first
      @api_key_pool = ApiKeyPool.new(@api_keys, concurrency_enabled: @enable_multi_key_concurrency)
    end
  end
end

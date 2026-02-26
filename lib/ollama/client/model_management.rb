# frozen_string_literal: true

module Ollama
  class Client
    # Model management endpoints: CRUD, pull/push, list, show, version
    module ModelManagement # rubocop:disable Metrics/ModuleLength
      # Show model details
      #
      # @param model [String] Model name (required)
      # @param verbose [Boolean] Include large verbose fields
      # @return [Hash] Model information (parameters, license, capabilities, details, model_info, template)
      def show_model(model:, verbose: false)
        show_uri = URI("#{@config.base_url}/api/show")
        req = Net::HTTP::Post.new(show_uri)
        req["Content-Type"] = "application/json"
        body = { model: model }
        body[:verbose] = true if verbose
        req.body = body.to_json

        res = http_request(show_uri, req)
        handle_http_error(res, requested_model: model) unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body)
        parsed["capabilities"] = Capabilities.for(parsed)
        parsed
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse show response: #{e.message}"
      end

      # Delete a model
      #
      # @param model [String] Model name to delete (required)
      # @return [true]
      def delete_model(model:) # rubocop:disable Naming/PredicateMethod
        delete_uri = URI("#{@config.base_url}/api/delete")
        req = Net::HTTP::Delete.new(delete_uri)
        req["Content-Type"] = "application/json"
        req.body = { model: model }.to_json

        res = http_request(delete_uri, req)
        handle_http_error(res, requested_model: model) unless res.is_a?(Net::HTTPSuccess)
        true
      end

      # Copy a model
      #
      # @param source [String] Existing model name to copy from (required)
      # @param destination [String] New model name to create (required)
      # @return [true]
      def copy_model(source:, destination:) # rubocop:disable Naming/PredicateMethod
        copy_uri = URI("#{@config.base_url}/api/copy")
        req = Net::HTTP::Post.new(copy_uri)
        req["Content-Type"] = "application/json"
        req.body = { source: source, destination: destination }.to_json

        res = http_request(copy_uri, req)
        handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
        true
      end

      # Create a model from an existing model
      #
      # @param model [String] Name for the model to create (required)
      # @param from [String] Existing model to create from (required)
      # @param system [String, nil] System prompt to embed
      # @param template [String, nil] Prompt template
      # @param license [String, Array<String>, nil] License string(s)
      # @param parameters [Hash, nil] Key-value parameters
      # @param messages [Array<Hash>, nil] Message history
      # @param quantize [String, nil] Quantization level (e.g. "q4_K_M", "q8_0")
      # @param stream [Boolean] Stream status updates
      # @return [Hash] Final status response
      # rubocop:disable Metrics/ParameterLists
      def create_model(model:, from:, system: nil, template: nil, license: nil,
                       parameters: nil, messages: nil, quantize: nil, stream: false)
        create_uri = URI("#{@config.base_url}/api/create")
        req = Net::HTTP::Post.new(create_uri)
        req["Content-Type"] = "application/json"

        body = { model: model, from: from, stream: stream }
        body[:system] = system if system
        body[:template] = template if template
        body[:license] = license if license
        body[:parameters] = parameters if parameters
        body[:messages] = messages if messages
        body[:quantize] = quantize if quantize
        req.body = body.to_json

        res = http_request(create_uri, req, read_timeout: @config.timeout * 5)
        handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse create response: #{e.message}"
      end
      # rubocop:enable Metrics/ParameterLists

      # Push a model to the registry
      #
      # @param model [String] Model name to push (required)
      # @param insecure [Boolean] Allow insecure connections
      # @param stream [Boolean] Stream progress updates
      # @return [Hash] Final status response
      def push_model(model:, insecure: false, stream: false)
        push_uri = URI("#{@config.base_url}/api/push")
        req = Net::HTTP::Post.new(push_uri)
        req["Content-Type"] = "application/json"

        body = { model: model, stream: stream }
        body[:insecure] = true if insecure
        req.body = body.to_json

        res = http_request(push_uri, req, read_timeout: @config.timeout * 10)
        handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse push response: #{e.message}"
      end

      # Pull a model explicitly
      #
      # @param model_name [String] Model name to download
      # @return [true]
      def pull(model_name)
        pull_uri = URI("#{@config.base_url}/api/pull")
        req = Net::HTTP::Post.new(pull_uri)
        req["Content-Type"] = "application/json"
        req.body = { model: model_name, stream: false }.to_json

        res = Net::HTTP.start(
          pull_uri.hostname,
          pull_uri.port,
          read_timeout: @config.timeout * 10,
          open_timeout: @config.timeout
        ) { |http| http.request(req) }

        handle_http_error(res, requested_model: model_name) unless res.is_a?(Net::HTTPSuccess)
        true
      rescue Net::ReadTimeout, Net::OpenTimeout
        raise TimeoutError, "Pull request timed out"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        raise Error, "Connection failed during pull: #{e.message}"
      end

      # List available models with full details
      #
      # @return [Array<Hash>] Array of model hashes with name, model, size, details, etc.
      def list_models
        tags_uri = URI("#{@config.base_url}/api/tags")
        req = Net::HTTP::Get.new(tags_uri)

        res = http_request(tags_uri, req)
        raise Error, "Failed to fetch models: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        models = body["models"] || []
        models.each { |m| m["capabilities"] = Capabilities.for(m) }
        models
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse models response: #{e.message}"
      end
      alias tags list_models

      # List model names only (convenience method)
      #
      # @return [Array<String>] Array of model name strings
      def list_model_names
        list_models.map { |m| m["name"] }
      end

      # List currently running/loaded models
      #
      # @return [Array<Hash>] Array of running model hashes with name, size, vram, context_length, etc.
      def list_running
        ps_uri = URI("#{@config.base_url}/api/ps")
        req = Net::HTTP::Get.new(ps_uri)

        res = http_request(ps_uri, req)
        raise Error, "Failed to fetch running models: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        models = body["models"] || []
        models.each { |m| m["capabilities"] = Capabilities.for(m) }
        models
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse running models response: #{e.message}"
      end
      alias ps list_running

      # Get Ollama server version
      #
      # @return [String] Version string (e.g. "0.12.6")
      def version
        version_uri = URI("#{@config.base_url}/api/version")
        req = Net::HTTP::Get.new(version_uri)

        res = http_request(version_uri, req)
        raise Error, "Failed to fetch version: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        body["version"]
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse version response: #{e.message}"
      end
    end
  end
end

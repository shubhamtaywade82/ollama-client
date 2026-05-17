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
      def delete_model(model:)
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
      def copy_model(source:, destination:)
        copy_uri = URI("#{@config.base_url}/api/copy")
        req = Net::HTTP::Post.new(copy_uri)
        req["Content-Type"] = "application/json"
        req.body = { source: source, destination: destination }.to_json

        res = http_request(copy_uri, req)
        handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
        true
      end

      # Create a model from an existing model, a Modelfile, or a path
      #
      # @param model [String] Name for the model to create (required)
      # @param from [String, nil] Existing model to create from
      # @param modelfile [String, nil] Raw content of a Modelfile
      # @param path [String, nil] Path to a Modelfile on the server
      # @param system [String, nil] System prompt to embed
      # @param template [String, nil] Prompt template
      # @param license [String, Array<String>, nil] License string(s)
      # @param parameters [Hash, nil] Key-value parameters
      # @param messages [Array<Hash>, nil] Message history
      # @param quantize [String, nil] Quantization level (e.g. "q4_K_M", "q8_0")
      # @param stream [Boolean] Stream status updates
      # @return [Hash] Final status response
      # rubocop:disable Metrics/ParameterLists
      def create_model(model:, from: nil, modelfile: nil, path: nil, system: nil, template: nil, license: nil,
                       parameters: nil, messages: nil, quantize: nil, stream: false)
        raise ArgumentError, "One of from:, modelfile:, or path: is required" if from.nil? && modelfile.nil? && path.nil?

        create_uri = URI("#{@config.base_url}/api/create")
        req = Net::HTTP::Post.new(create_uri)
        req["Content-Type"] = "application/json"

        body = { model: model, stream: stream }
        body[:from] = from if from
        body[:modelfile] = modelfile if modelfile
        body[:path] = path if path
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

      # Check if a blob exists on the server
      #
      # @param digest [String] The digest of the blob (required)
      # @return [Boolean] True if exists, false otherwise
      def blob_exists?(digest:)
        blob_uri = URI("#{@config.base_url}/api/blobs/#{digest}")
        req = Net::HTTP::Head.new(blob_uri)

        res = http_request(blob_uri, req)
        res.is_a?(Net::HTTPSuccess)
      rescue NotFoundError
        false
      end

      # Create a blob by uploading content
      #
      # @param digest [String] The digest of the blob (required)
      # @param content [String] The raw content of the blob
      # @return [true]
      def create_blob(digest:, content:)
        blob_uri = URI("#{@config.base_url}/api/blobs/#{digest}")
        req = Net::HTTP::Post.new(blob_uri)
        req.body = content

        res = http_request(blob_uri, req)
        handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
        true
      end

      # Push a model to the registry
      #
      # @param model [String] Model name to push (required)
      # @param insecure [Boolean] Allow insecure connections
      # @param stream [Boolean] Stream progress updates
      # @param hooks [Hash] Callbacks for streaming progress (:on_progress)
      # @return [Hash, true] Final status or true if not streaming
      def push_model(model:, insecure: false, stream: false, hooks: {})
        push_uri = URI("#{@config.base_url}/api/push")
        req = Net::HTTP::Post.new(push_uri)
        req["Content-Type"] = "application/json"

        body = { model: model, stream: stream }
        body[:insecure] = true if insecure
        req.body = body.to_json

        if stream
          handle_ndjson_stream(push_uri, req, hooks)
        else
          res = http_request(push_uri, req, read_timeout: @config.timeout * 10)
          handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
          JSON.parse(res.body)
        end
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse push response: #{e.message}"
      end

      # Pull a model from the registry
      #
      # @param model_name [String] Model name to download
      # @param insecure [Boolean] Allow insecure connections
      # @param stream [Boolean] Stream progress updates
      # @param hooks [Hash] Callbacks for streaming progress (:on_progress)
      # @return [Hash, true] Final status or true if not streaming
      def pull(model_name, insecure: false, stream: false, hooks: {})
        pull_uri = URI("#{@config.base_url}/api/pull")
        req = Net::HTTP::Post.new(pull_uri)
        req["Content-Type"] = "application/json"
        body = { model: model_name, stream: stream }
        body[:insecure] = true if insecure
        req.body = body.to_json
        @config.apply_auth_to(req)

        if stream
          handle_ndjson_stream(pull_uri, req, hooks)
        else
          res = http_request(pull_uri, req, read_timeout: @config.timeout * 10)
          handle_http_error(res, requested_model: model_name) unless res.is_a?(Net::HTTPSuccess)
          JSON.parse(res.body)
        end
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse pull response: #{e.message}"
      end

      # Explicitly load a model into memory
      #
      # @param model [String] Model name (required)
      # @param keep_alive [String, Integer] Keep-alive duration (default "5m")
      # @return [true]
      def load_model(model:, keep_alive: "5m")
        generate_uri = URI("#{@config.base_url}/api/generate")
        req = Net::HTTP::Post.new(generate_uri)
        req["Content-Type"] = "application/json"
        req.body = { model: model, prompt: "", keep_alive: keep_alive, stream: false }.to_json

        res = http_request(generate_uri, req)
        handle_http_error(res, requested_model: model) unless res.is_a?(Net::HTTPSuccess)
        true
      end

      # Unload a model from memory
      #
      # @param model [String] Model name (required)
      # @return [true]
      def unload_model(model:)
        load_model(model: model, keep_alive: 0)
      end

      # List available models with full details
      #
      # @return [Array<Hash>] Array of model hashes with name, model, size, details, etc.
      def list_models
        tags_uri = @provider.models_endpoint
        req = Net::HTTP::Get.new(tags_uri)

        res = http_request(tags_uri, req)
        raise Error, "Failed to fetch models: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        body = @provider.normalize_models_response(JSON.parse(res.body))
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
        return nil if @provider.is_a?(Providers::OpenAI)

        version_uri = URI("#{@config.base_url}/api/version")
        req = Net::HTTP::Get.new(version_uri)

        res = http_request(version_uri, req)
        raise Error, "Failed to fetch version: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        body["version"]
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse version response: #{e.message}"
      end

      private

      def handle_ndjson_stream(uri, req, hooks)
        last_status = nil
        Net::HTTP.start(uri.hostname, uri.port, **@config.http_connection_options(uri, read_timeout: @config.timeout * 20)) do |http|
          http.request(req) do |res|
            handle_http_error(res) unless res.is_a?(Net::HTTPSuccess)
            res.read_body do |chunk|
              chunk.split("\n").each do |line|
                next if line.strip.empty?

                status = JSON.parse(line)
                hooks[:on_progress]&.call(status)
                last_status = status
              end
            end
          end
        end
        last_status
      end
    end
  end
end

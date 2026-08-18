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
        body = { model: model }
        body[:verbose] = true if verbose
        res = execute_management_request("/api/show", body: body, model: model)
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
        execute_management_request("/api/delete", method: :delete, body: { model: model }, model: model)
        true
      end

      # Copy a model
      #
      # @param source [String] Existing model name to copy from (required)
      # @param destination [String] New model name to create (required)
      # @return [true]
      def copy_model(source:, destination:)
        execute_management_request("/api/copy", body: { source: source, destination: destination })
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
        # rubocop:enable Metrics/ParameterLists
        params = Params::CreateModel.new(
          model: model, from: from, modelfile: modelfile, path: path, system: system,
          template: template, license: license, parameters: parameters, messages: messages,
          quantize: quantize, stream: stream
        )
        create_model_with_params(params)
      end

      # @param params [Ollama::Params::CreateModel] Model creation parameters
      # @return [Hash] Final status response
      def create_model_with_params(params)
        if params.from.nil? && params.modelfile.nil? && params.path.nil?
          raise ArgumentError,
                "One of from:, modelfile:, or path: is required"
        end

        res = execute_management_request("/api/create", body: params.to_h, read_timeout: @config.timeout * 5)
        JSON.parse(res.body)
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse create response: #{e.message}"
      end

      # Check if a blob exists on the server
      #
      # @param digest [String] The digest of the blob (required)
      # @return [Boolean] True if exists, false otherwise
      def blob_exists?(digest:)
        res = execute_management_request("/api/blobs/#{digest}", method: :head)
        res.is_a?(Net::HTTPSuccess)
      rescue NotFoundError, Error
        false
      end

      # Create a blob by uploading content
      #
      # @param digest [String] The digest of the blob (required)
      # @param content [String] The raw content of the blob
      # @return [true]
      def create_blob(digest:, content:) # rubocop:disable Naming/PredicateMethod
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
        params = Params::ModelTransfer.new(model: model, insecure: insecure, stream: stream, hooks: hooks)
        push_model_with_params(params)
      end

      # @param params [Ollama::Params::ModelTransfer] Push parameters
      # @return [Hash, true] Final status or true if not streaming
      def push_model_with_params(params)
        body = { model: params.model, stream: params.stream }
        body[:insecure] = true if params.insecure

        push_uri = URI("#{@config.base_url}/api/push")
        req = Net::HTTP::Post.new(push_uri)
        req["Content-Type"] = "application/json"
        req.body = body.to_json

        if params.stream
          handle_ndjson_stream(push_uri, req, params.hooks)
        else
          res = execute_management_request("/api/push", body: body, read_timeout: @config.timeout * 10)
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
        params = Params::ModelTransfer.new(model: model_name, insecure: insecure, stream: stream, hooks: hooks)
        pull_with_params(params)
      end

      # @param params [Ollama::Params::ModelTransfer] Pull parameters
      # @return [Hash, true] Final status or true if not streaming
      def pull_with_params(params)
        body = { model: params.model, stream: params.stream }
        body[:insecure] = true if params.insecure

        pull_uri = URI("#{@config.base_url}/api/pull")
        req = Net::HTTP::Post.new(pull_uri)
        req["Content-Type"] = "application/json"
        req.body = body.to_json
        @config.apply_auth_to(req)

        if params.stream
          handle_ndjson_stream(pull_uri, req, params.hooks)
        else
          res = execute_management_request("/api/pull", body: body, model: params.model, read_timeout: @config.timeout * 10)
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
      def load_model(model:, keep_alive: "5m") # rubocop:disable Naming/PredicateMethod
        execute_management_request("/api/generate", body: { model: model, prompt: "", keep_alive: keep_alive, stream: false },
                                                    model: model)
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
        res = execute_management_request(@provider.models_endpoint, method: :get)
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
        res = execute_management_request("/api/ps", method: :get)
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

        res = execute_management_request("/api/version", method: :get)
        body = JSON.parse(res.body)
        body["version"]
      rescue JSON::ParserError => e
        raise InvalidJSONError, "Failed to parse version response: #{e.message}"
      end

      private

      def execute_management_request(path_or_uri, method: :post, body: nil, model: nil, read_timeout: nil)
        uri = path_or_uri.is_a?(URI) ? path_or_uri : URI("#{@config.base_url}#{path_or_uri}")
        req = case method
              when :delete then Net::HTTP::Delete.new(uri)
              when :get then Net::HTTP::Get.new(uri)
              when :head then Net::HTTP::Head.new(uri)
              else Net::HTTP::Post.new(uri)
              end
        req["Content-Type"] = "application/json"
        req.body = body.to_json if body && method != :get && method != :head

        res = if read_timeout
                http_request(uri, req, read_timeout: read_timeout)
              else
                http_request(uri, req)
              end

        unless res.is_a?(Net::HTTPSuccess)
          raise Error, "Failed request to #{uri.path}: HTTP #{res.code}" if %i[get head].include?(method)

          handle_http_error(res, requested_model: model)

        end
        res
      end

      def handle_ndjson_stream(uri, req, hooks)
        last_status = nil

        with_rate_limit_key_rotation do |api_key|
          last_status = nil
          @config.apply_auth_to(req, api_key: api_key)

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
        end

        last_status
      end
    end
  end
end

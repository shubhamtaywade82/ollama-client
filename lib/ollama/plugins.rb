# frozen_string_literal: true

# Ollama - A Ruby client for the Ollama API
module Ollama
  # Plugin system for the Ollama client.
  # Allows registering plugins that can add middleware, configure defaults, etc.
  class Plugins
    def initialize
      @plugins = []
    end

    # Register a plugin
    # @param plugin [Module, Class] Plugin module/class
    # @param config [Hash] Configuration for the plugin
    # @return [Ollama::Plugins] self
    def register(plugin, config: {})
      @plugins << { plugin: plugin, config: config }
      self
    end

    # Apply all registered plugins to a client
    # @param client [Ollama::Client] Client instance
    # @return [Ollama::Plugins] self
    def apply_all(client)
      @plugins.each do |p|
        plugin = p[:plugin]
        config = p[:config]
        plugin.apply(client, config) if plugin.respond_to?(:apply)
      end
      self
    end

    # Apply a specific plugin to a client
    # @param plugin [Module, Class] Plugin to apply
    # @param client [Ollama::Client] Client instance
    # @param config [Hash] Configuration
    # @return [Boolean] True if plugin was found and applied
    def apply_plugin?(plugin, client, config = {})
      entry = @plugins.find { |p| p[:plugin] == plugin }
      return false unless entry

      plugin.apply(client, config) if plugin.respond_to?(:apply)
      true
    end

    # List registered plugins
    # @return [Array<Module, Class>] List of plugin classes/modules
    def list
      @plugins.map { |p| p[:plugin] }
    end

    # Check if a plugin is registered
    # @param plugin [Module, Class] Plugin to check
    # @return [Boolean]
    def registered?(plugin)
      @plugins.any? { |p| p[:plugin] == plugin }
    end
  end

  # Global plugin registry
  @plugins = Plugins.new

  class << self
    # Get the global plugin registry
    # @return [Ollama::Plugins]
    attr_reader :plugins

    # Register a plugin globally
    # @param plugin [Module, Class] Plugin module/class
    # @param config [Hash] Plugin configuration
    # @return [Ollama::Plugins] The registry
    def plugin(plugin, config: {})
      @plugins.register(plugin, config: config)
    end

    # Apply all plugins to a client
    # @param client [Ollama::Client] Client instance
    # @return [Ollama::Plugins] The registry
    def apply_plugins(client)
      @plugins.apply_all(client)
    end
  end
end

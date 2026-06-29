# frozen_string_literal: true

module Ollama
  # Event system for the Ollama client.
  # Provides pub/sub for request lifecycle events.
  class Events
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end

    # Subscribe to an event
    # @param event [Symbol] Event name
    # @param block [Proc] Callback to execute
    # @return [Proc] The subscribed block
    def subscribe(event, &block)
      @subscribers[event] << block
      block
    end

    # Unsubscribe from an event
    # @param event [Symbol] Event name
    # @param block [Proc] The block to remove
    # @return [Boolean] True if block was found and removed
    def unsubscribe(event, block)
      @subscribers[event].delete(block)
    end

    # Publish an event to all subscribers
    # @param event [Symbol] Event name
    # @param payload [Hash] Event data
    # @return [Array] Results from all subscribers
    def publish(event, payload = {})
      @subscribers[event].map do |subscriber|
        subscriber.call(payload)
      rescue StandardError => e
        warn "[Ollama::Events] Subscriber error for #{event}: #{e.message}"
        nil
      end
    end

    # Clear all subscribers for an event
    # @param event [Symbol] Event name
    # @return [Integer] Number of subscribers cleared
    def clear(event)
      count = @subscribers[event].size
      @subscribers[event].clear
      count
    end

    # Clear all subscribers for all events
    def clear_all
      @subscribers.clear
    end
  end
end

# frozen_string_literal: true

module Ollama
  # Thread-safe immutable API key pool for rate-limit failover.
  #
  # The pool never mutates the configured key list after construction. Request
  # state is represented as a short-lived context hash so retry counters and
  # rotation offsets remain isolated to the caller's execution path.
  class ApiKeyPool
    attr_reader :keys

    # @param keys [Array<String>] API keys in configured priority order
    # @param concurrency_enabled [Boolean] whether initial keys should be distributed round-robin
    def initialize(keys, concurrency_enabled: false)
      @keys = keys.map(&:to_s).map(&:strip).reject(&:empty?).freeze
      @concurrency_enabled = concurrency_enabled
      @mutex = Mutex.new
      @next_index = 0
    end

    # @return [Integer] number of configured keys
    def size
      @keys.size
    end

    # @return [Boolean] true when no keys are configured
    def empty?
      @keys.empty?
    end

    # Build request-local rotation context.
    #
    # @return [Hash] isolated context for one logical request attempt
    def request_context
      { start_index: initial_index }
    end

    # Resolve a key from a request-local context and rotation offset.
    #
    # @param context [Hash]
    # @param offset [Integer]
    # @return [String, nil]
    def key_for(context, offset: 0)
      return nil if empty?

      @keys[(context.fetch(:start_index) + offset) % size]
    end

    private

    def initial_index
      return 0 unless @concurrency_enabled

      @mutex.synchronize do
        current = @next_index
        @next_index = (@next_index + 1) % size if size.positive?
        current
      end
    end
  end
end

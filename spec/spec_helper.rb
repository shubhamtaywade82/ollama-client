# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/.bundle/"
  add_filter "/bin/"
  add_filter "/exe/"
  add_filter "/examples/"
end

require "ollama_client"
require "webmock/rspec"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # WebMock configuration
  config.before do |example|
    WebMock.reset!
    # Allow real connections for integration tests
    if example.metadata[:integration]
      WebMock.allow_net_connect!
    else
      WebMock.disable_net_connect!(allow_localhost: false)
    end
  end

  # Ensure WebMock allows connections for integration tests
  config.before(:each, :integration) do
    WebMock.allow_net_connect!
  end

  config.after(:each, :integration) do
    # Keep allowing for next integration test
    WebMock.allow_net_connect!
  end

  config.after do |example|
    # Re-disable after non-integration tests
    WebMock.disable_net_connect!(allow_localhost: false) unless example.metadata[:integration]
  end
end

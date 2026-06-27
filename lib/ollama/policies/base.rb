# frozen_string_literal: true

require_relative "../../middleware"

module Ollama
  module Policies
    # Base class for all policies.
    # Policies are middleware that implement production behaviors (retry, timeout, etc.)
    class Base < Ollama::Middleware
    end
  end
end

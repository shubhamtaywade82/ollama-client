# frozen_string_literal: true

# NOTE: lib/ollama/policies/ is unfinished scaffolding, not wired into
# Ollama::Client. Every policy in this namespace implements a Rack-style
# `call(request, env)` that delegates to `@app.call(request, env)` as the
# next step in a chain — but nothing ever assigns `@app` (no constructor
# wiring, no chain builder), so calling any policy's #call raises
# NoMethodError on nil. The behaviors these policies model (retry with
# backoff, auto-pull on 404, JSON/schema repair, timeouts) already exist
# in Client today as separate inline implementations — see
# API_CONTRACT.md's "Recovery Behaviors" and docs/RUBYLLM_ADOPTION_MATRIX.md
# G6, which tracks formalizing a middleware/policy stack as future work.
# Left in place (not required by default, not deleted) so that work has
# somewhere to start from.

require_relative "../middleware"

module Ollama
  module Policies
    # Base class for all policies.
    # Policies are middleware that implement production behaviors (retry, timeout, etc.)
    class Base < Ollama::Middleware
    end
  end
end

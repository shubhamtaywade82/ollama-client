# frozen_string_literal: true

# Production-behavior middleware policies for Ollama::Client.
#
# Attach to a client with `client.use`:
#   client.use(Ollama::Policies::Retry, max_attempts: 3)
#   client.use(Ollama::Policies::Timeout, read_timeout: 30)
#   client.use(Ollama::Policies::AutoPull)
#   client.use(Ollama::Policies::RateLimit, requests_per_second: 10)
#   client.use(Ollama::Policies::CapabilityValidation)
#   client.use(Ollama::Policies::Fallback, models: %w[gemma4:31b llama3.1:8b])
#   client.use(Ollama::Policies::RepairJson)
#   client.use(Ollama::Policies::SchemaRepair)
#
# Chain order matters: policies wrap the ones registered after them.
require_relative "policies/base"
require_relative "policies/retry"
require_relative "policies/timeout"
require_relative "policies/rate_limit"
require_relative "policies/auto_pull"
require_relative "policies/capability_validation"
require_relative "policies/fallback"
require_relative "policies/repair_json"
require_relative "policies/schema_repair"

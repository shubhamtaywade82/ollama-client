# Cloud Agent Guide

This repository is a Ruby gem. It has no database and does not require
application secrets for the default test suite.

## Required Commands
- `bundle install`
- `bundle exec rubocop`
- `bundle exec rspec`

## Agent Prompt Template
You are operating on a Ruby gem repository.
Task:
1. Run `bundle exec rubocop`.
2. Fix all RuboCop offenses.
3. Re-run RuboCop until clean.
4. Run `bundle exec rspec`.
5. Fix all failing specs.
6. Re-run RSpec until green.

Rules:
- Do not skip failures.
- Do not change public APIs without reporting.
- Do not bump gem version unless explicitly told.
- Stop if blocked and explain why.

## Guardrails
- Keep API surface stable and backward compatible.
- Update specs when behavior changes.

## Ollama Cloud Model Accessibility

Ollama Cloud does not expose a `free` flag per model. The only reliable way to determine whether a model is accessible to your account is to attempt a tiny inference and observe the HTTP response.

The project includes a standalone example script that automates this:

```bash
export OLLAMA_API_KEY="your-ollama-cloud-api-key"
bundle exec ruby examples/cloud_models.rb
```

The script:
1. Fetches the public cloud model catalog from `https://ollama.com/api/tags`
2. Probes each model concurrently (10 threads) with a minimal chat request
3. Classifies the response into accessibility statuses (`accessible`, `unauthorized`, `plan_restricted`, `usage_limit`, `unavailable`, `rate_limited`, `timeout`, etc.)
4. Prints sorted JSON to stdout

See [`examples/cloud_models.rb`](../examples/cloud_models.rb) for the full implementation and [`examples/README.md`](../examples/README.md) for usage details.

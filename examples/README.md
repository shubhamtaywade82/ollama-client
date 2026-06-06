# Examples

This directory contains working example scripts demonstrating various capabilities of `ollama-client`.

## Running Examples

Most examples assume you are in the project root and use `require_relative` to load the local gem:

```bash
bundle exec ruby examples/<script>.rb
```

## Overview

| Script | What it demonstrates |
|---|---|
| [`agent_loop.rb`](agent_loop.rb) | Agentic loop with tool calling and stateful memory |
| [`cloud_models.rb`](cloud_models.rb) | List Ollama Cloud models and probe which ones your account can access |
| [`llama_cpp_gpu_test.rb`](llama_cpp_gpu_test.rb) | Connect to a llama.cpp GPU server via the OpenAI provider |
| [`timeout_retry.rb`](timeout_retry.rb) | How timeout and exponential backoff work in production |
| [`failure_modes/invalid_json_repair.rb`](failure_modes/invalid_json_repair.rb) | Automatic JSON repair when the model returns markdown-wrapped JSON |
| [`production/rails_agent.rb`](production/rails_agent.rb) | Resilient background job pattern for Rails (e.g. Sidekiq) |

## Cloud Model Accessibility Probe

[`cloud_models.rb`](cloud_models.rb) is useful if you use Ollama Cloud and want to know which models are available under your current plan:

```bash
export OLLAMA_API_KEY="your-ollama-cloud-api-key"
bundle exec ruby examples/cloud_models.rb
```

Output is JSON printed to stdout:

```json
[
  { "name": "gpt-oss:20b", "accessible": true, "reason": null },
  { "name": "deepseek-v4-pro", "accessible": false, "reason": "plan_restricted" }
]
```

See the script's header comments for the full list of `reason` codes.

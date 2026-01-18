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

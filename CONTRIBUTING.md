# Contributing

Thanks for helping improve `ollama-client`.

## Scope & philosophy

- This gem is **agent-first**: it optimizes for **deterministic planners** and **safe tool-using executors**.
- The LLM **never executes tools**. Tools are always Ruby callables executed outside the model.
- We prefer **explicitness over magic**:
  - Bounded retries with clear errors
  - Strict JSON / schema contracts
  - Gated chat usage to prevent accidental misuse

## Development

```bash
bundle install
bundle exec rake
```

## What to include in a PR

- Clear description of *why* the change exists (not just what changed)
- Tests for behavior changes (RSpec)
- README updates if you changed public behavior or expectations

## Reporting issues

Please include:

- Ruby version
- Gem version
- Ollama version (if known)
- Minimal reproduction (a small script is best)
- Expected vs actual behavior


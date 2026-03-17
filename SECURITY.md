# Security Policy

## Supported Versions

Only the current major version is supported for security updates.

| Version | Supported          |
| ------- | ------------------ |
| v1.0.x  | :white_check_mark: |
| < v1.0  | :x:                |

## Reporting a Vulnerability

If you discover any security related issues, please email our security team directly instead of using the issue tracker. You will receive an acknowledgment within 48 hours and a targeted resolution timeline.

### Thread Safety Warning
Starting from `v1.0.0`, mutating `OllamaClient.configure` inside concurrent threads is considered unsafe and not treated as a security vulnerability. Always instantiate locally structured `Ollama::Client.new(config: ...)` when scaling inside Rails job runners like Sidekiq.

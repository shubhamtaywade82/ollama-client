# Internal Documentation

This directory contains internal development documentation for the ollama-client gem.

## Quick Links

- 🚀 **[Release Guide](RELEASE_GUIDE.md)** - Complete guide for automated gem releases with MFA

## Contents

### Design Documentation
- **[HANDLERS_ANALYSIS.md](HANDLERS_ANALYSIS.md)** - Analysis of handler architecture decisions (why we didn't adopt ollama-ruby's handler pattern)
- **[FEATURES_ADDED.md](FEATURES_ADDED.md)** - Features integrated from ollama-ruby that align with our agent-first philosophy
- **[PRODUCTION_FIXES.md](PRODUCTION_FIXES.md)** - Production-ready fixes for hybrid agents (JSON parsing, retry policy, etc.)
- **[SCHEMA_FIXES.md](SCHEMA_FIXES.md)** - Schema validation fixes and best practices for numeric constraints
- **[CONSOLE_IMPROVEMENTS.md](CONSOLE_IMPROVEMENTS.md)** - Interactive console UX improvements (thinking indicators, formatted tool results)

### Testing Documentation
- **[TESTING.md](TESTING.md)** - Testing guide and examples
- **[TEST_UPDATES.md](TEST_UPDATES.md)** - Recent test updates for DhanHQ tool calling enhancements

### CI/Automation
- **[CLOUD.md](CLOUD.md)** - Cloud agent guide for automated testing and fixes
- **[RELEASE_GUIDE.md](RELEASE_GUIDE.md)** - Complete guide for automated gem releases via GitHub Actions with OTP/MFA

## For Users

If you're looking for user-facing documentation, see:
- [Main README](../README.md) - Getting started, API reference, examples
- [CHANGELOG](../CHANGELOG.md) - Version history and changes
- [CONTRIBUTING](../CONTRIBUTING.md) - How to contribute
- [Examples](../examples/) - Working code examples

## For Contributors

These internal docs help maintainers understand:
- **Why** certain design decisions were made
- **What** features have been added and why
- **How** to test and maintain the codebase
- **Where** production fixes were applied

They are not intended for end users and can be safely ignored when using the gem.

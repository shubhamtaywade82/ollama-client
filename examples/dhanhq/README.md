# DhanHQ Agent - Refactored Architecture

## Structure

```
dhanhq/
├── agents/           # Agent classes (LLM decision makers)
│   ├── base_agent.rb
│   ├── data_agent.rb
│   └── trading_agent.rb
├── services/         # Service classes (API executors)
│   ├── base_service.rb
│   ├── data_service.rb
│   └── trading_service.rb
├── builders/         # Builder classes (data transformation)
│   └── market_context_builder.rb
├── utils/            # Utility classes
│   ├── instrument_helper.rb
│   ├── parameter_normalizer.rb
│   ├── parameter_cleaner.rb
│   └── rate_limiter.rb
├── schemas/          # JSON schemas for LLM
│   └── agent_schemas.rb
└── dhanhq_agent.rb   # Main entry point
```

## Design Principles

- **SOLID**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **KISS**: Keep It Simple, Stupid
- **DRY**: Don't Repeat Yourself
- **Namespacing**: All classes under `DhanHQ` module

## Usage

```ruby
require_relative "dhanhq/dhanhq_agent"

agent = DhanHQ::Agent.new
decision = agent.data_agent.analyze_and_decide(market_context: "...")
result = agent.data_agent.execute_decision(decision)
```

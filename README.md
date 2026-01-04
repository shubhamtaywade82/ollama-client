# Ollama::Client

A **low-level, opinionated Ollama client** for **LLM-based hybrid agents**,
**NOT** a chatbot,
**NOT** domain-specific,
**NOT** a framework.

This gem provides:

* ✅ Safe LLM calls
* ✅ Strict output contracts
* ✅ Retry & timeout handling
* ✅ Zero hidden state
* ✅ Extensible schemas

Everything else (tools, agents, domains) lives **outside** this gem.

## 🎯 What This Gem IS

* LLM call executor
* Output validator
* Retry + timeout manager
* Schema enforcer

## 🚫 What This Gem IS NOT

* ❌ Agent loop
* ❌ Tool router
* ❌ Domain logic
* ❌ Memory store
* ❌ Chat UI

This keeps it **clean and future-proof**.

## 🔒 Guarantees

| Guarantee              | Yes |
| ---------------------- | --- |
| Stateless              | ✅   |
| Retry bounded          | ✅   |
| Schema validated       | ✅   |
| Deterministic defaults | ✅   |
| Agent-safe             | ✅   |
| Domain-agnostic        | ✅   |

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ollama-client"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ollama-client
```

## Usage

### Basic Configuration

```ruby
require "ollama_client"

# Configure global defaults
OllamaClient.configure do |c|
  c.base_url = "http://localhost:11434"
  c.model = "llama3.1"
  c.timeout = 30
  c.retries = 3
  c.temperature = 0.2
end
```

### Example: Planning Agent

```ruby
client = Ollama::Client.new

schema = {
  "type" => "object",
  "required" => ["action"],
  "properties" => {
    "action" => { "type" => "string" },
    "reasoning" => { "type" => "string" }
  }
}

result = client.generate(
  prompt: "Analyze the current situation and decide the next step.",
  schema: schema
)

puts result["action"]
```

### Example: Analysis Agent

```ruby
schema = {
  "type" => "object",
  "required" => ["summary", "confidence"],
  "properties" => {
    "summary" => { "type" => "string" },
    "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
  }
}

client = Ollama::Client.new
result = client.generate(
  prompt: "Summarize the following data: #{data}",
  schema: schema
)
```

### Custom Configuration Per Client

```ruby
custom_config = Ollama::Config.new
custom_config.model = "qwen2.5:14b"
custom_config.temperature = 0.1

client = Ollama::Client.new(config: custom_config)
```

### Error Handling

```ruby
begin
  result = client.generate(prompt: prompt, schema: schema)
rescue Ollama::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Ollama::SchemaViolationError => e
  puts "Output didn't match schema: #{e.message}"
rescue Ollama::RetryExhaustedError => e
  puts "Failed after retries: #{e.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shubhamtaywade82/ollama-client. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ollama::Client project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/shubhamtaywade82/ollama-client/blob/main/CODE_OF_CONDUCT.md).

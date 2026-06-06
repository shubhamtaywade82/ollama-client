#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Agent - Complete trading agent with data retrieval and trading operations
# This entrypoint now delegates to a small folder structure under `examples/dhanhq_agent/`
# while preserving the original public surface area:
# - `DataAgent`
# - `TradingAgent`
# - `build_market_context_from_data`

require_relative "dhanhq_agent/runner"

# Backwards compatible constants (keep existing names)
DataAgent = DhanHQAgent::Agents::DataAgent
TradingAgent = DhanHQAgent::Agents::TradingAgent

# Backwards compatible helper (keep existing signature)
def build_market_context_from_data(market_data)
  DhanHQAgent::MarketContextBuilder.build(market_data)
end

DhanHQAgent::Runner.run if __FILE__ == $PROGRAM_NAME


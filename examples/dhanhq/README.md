# DhanHQ Agent - Complete Trading & Technical Analysis System

## Features

### Core Capabilities
- **Data Retrieval**: 6 DhanHQ Data APIs (Market Quote, LTP, Depth, Historical, Options, Chain)
- **Trading Tools**: Order parameter building (regular, super orders, cancel)
- **LLM-Powered Decisions**: Ollama for intelligent market analysis and decision making
- **LLM Orchestration**: AI decides what symbols to analyze, which exchange segments, and what analysis to run

### Technical Analysis (NEW!)
- **Trend Analysis**: Uptrend, downtrend, sideways detection with strength calculation
- **Market Structure**: SMC (Smart Money Concepts) analysis
  - Order blocks identification
  - Liquidity zones (buy-side/sell-side)
  - Structure breaks detection
- **Pattern Recognition**:
  - Candlestick patterns (engulfing, hammer, shooting star, etc.)
  - Chart patterns (head & shoulders, double top/bottom)
- **Technical Indicators**:
  - Moving Averages (SMA, EMA)
  - RSI (Relative Strength Index)
  - MACD (Moving Average Convergence Divergence)
  - Bollinger Bands
  - ATR (Average True Range)
  - Support & Resistance levels

### Scanners (NEW!)
- **Swing Trading Scanner**: Find swing trading candidates based on technical analysis
- **Intraday Options Scanner**: Find intraday options buying opportunities with IV/OI analysis

## Structure

```
dhanhq/
├── agents/                    # Agent classes (LLM decision makers)
│   ├── base_agent.rb
│   ├── data_agent.rb
│   ├── trading_agent.rb
│   ├── technical_analysis_agent.rb
│   └── orchestrator_agent.rb  # NEW - LLM decides what to analyze
├── services/                  # Service classes (API executors)
│   ├── base_service.rb
│   ├── data_service.rb
│   └── trading_service.rb
├── analysis/                  # Technical analysis modules (NEW)
│   ├── market_structure.rb    # SMC, trend, structure breaks
│   ├── pattern_recognizer.rb # Candlestick & chart patterns
│   └── trend_analyzer.rb     # Comprehensive trend analysis
├── indicators/                # Technical indicators (NEW)
│   └── technical_indicators.rb # RSI, MACD, MA, Bollinger, ATR, etc.
├── scanners/                  # Trading scanners (NEW)
│   ├── swing_scanner.rb      # Swing trading candidates
│   └── intraday_options_scanner.rb # Options opportunities
├── builders/                  # Builder classes
│   └── market_context_builder.rb
├── utils/                     # Utility classes
│   ├── instrument_helper.rb
│   ├── parameter_normalizer.rb
│   ├── parameter_cleaner.rb
│   ├── trading_parameter_normalizer.rb
│   └── rate_limiter.rb
├── schemas/                   # JSON schemas for LLM
│   └── agent_schemas.rb
└── dhanhq_agent.rb            # Main entry point
```

## Design Principles

- **SOLID**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **KISS**: Keep It Simple, Stupid
- **DRY**: Don't Repeat Yourself
- **Namespacing**: All classes under `DhanHQ` module

## Usage

### Basic Usage

```ruby
require_relative "dhanhq/dhanhq_agent"

agent = DhanHQ::Agent.new

# Data retrieval
decision = agent.data_agent.analyze_and_decide(market_context: "...")
result = agent.data_agent.execute_decision(decision)

# Trading
trading_decision = agent.trading_agent.analyze_and_decide(market_context: "...")
order_params = agent.trading_agent.execute_decision(trading_decision)
```

### LLM Orchestration (NEW!)

```ruby
# Let LLM decide what to analyze
plan = agent.orchestrator_agent.decide_analysis_plan(
  market_context: "NIFTY is at 25,790, RELIANCE showing strength",
  user_query: "Find swing trading opportunities in banking stocks"
)

# Plan contains:
# - analysis_plan: Array of tasks with symbol, exchange_segment, analysis_type
# - reasoning: Why the LLM chose this plan

# Execute the plan
plan["analysis_plan"].each do |task|
  case task["analysis_type"]
  when "technical_analysis"
    agent.analysis_agent.analyze_symbol(...)
  when "swing_scan"
    agent.swing_scanner.scan_symbols(...)
  when "options_scan"
    agent.options_scanner.scan_for_options_setups(...)
  end
end
```

### Technical Analysis

```ruby
# Analyze a symbol
analysis = agent.analysis_agent.analyze_symbol(
  symbol: "RELIANCE",
  exchange_segment: "NSE_EQ"
)

# Get swing trading recommendation
recommendation = agent.analysis_agent.generate_recommendation(
  analysis,
  trading_style: :swing
)
```

### Scanning

```ruby
# Swing trading scanner
candidates = agent.swing_scanner.scan_symbols(
  ["RELIANCE", "TCS", "INFY"],
  exchange_segment: "NSE_EQ"
)

# Intraday options scanner
options_setups = agent.options_scanner.scan_for_options_setups(
  "NIFTY",
  exchange_segment: "IDX_I"
)
```

## Technical Analysis Capabilities

### Trend Analysis
- Detects uptrend, downtrend, sideways
- Calculates trend strength percentage
- Uses moving averages for confirmation

### SMC (Smart Money Concepts)
- **Order Blocks**: Identifies institutional order zones
- **Liquidity Zones**: Finds buy-side and sell-side liquidity areas
- **Structure Breaks**: Detects trend changes and breakouts

### Pattern Recognition
- **Candlestick Patterns**: Engulfing, hammer, shooting star, three white soldiers/crows
- **Chart Patterns**: Head & shoulders, double top/bottom

### Indicators
- **RSI**: Overbought/oversold conditions
- **MACD**: Momentum and trend changes
- **Moving Averages**: Trend confirmation
- **Bollinger Bands**: Volatility and mean reversion
- **ATR**: Volatility measurement
- **Support/Resistance**: Key price levels

## Scanner Features

### Swing Trading Scanner
- Scores symbols based on:
  - Trend strength
  - RSI levels (prefers 40-60 zone)
  - MACD bullish crossovers
  - Structure breaks
  - Pattern recognition
- Returns top candidates sorted by score

### Intraday Options Scanner
- Analyzes underlying trend
- Finds ATM/near-ATM strikes
- Considers:
  - Implied Volatility (lower is better for buying)
  - Open Interest (higher is better)
  - Volume (higher is better)
  - Trend alignment
  - RSI levels
- Returns top 5 setups with scores

## Running

### Full Demo (All Features)
```bash
ruby examples/dhanhq/dhanhq_agent.rb
```

This will demonstrate:
1. Data retrieval with LLM decisions
2. Trading order parameter building
3. Technical analysis for a symbol
4. Swing trading scanner
5. Intraday options scanner

### Technical Analysis Only
```bash
# LLM decides what to analyze (default)
ruby examples/dhanhq/technical_analysis_runner.rb

# With custom query
ruby examples/dhanhq/technical_analysis_runner.rb "Find options opportunities for NIFTY"

# With custom query and market context
ruby examples/dhanhq/technical_analysis_runner.rb "Analyze banking stocks" "Banking sector showing strength"

# Show manual examples too (for comparison)
SHOW_MANUAL_EXAMPLES=true ruby examples/dhanhq/technical_analysis_runner.rb
```

**LLM-Powered Orchestration:**
The LLM decides:
- Which symbols to analyze (e.g., "RELIANCE", "NIFTY", "BANKNIFTY")
- Which exchange segments to use (NSE_EQ, IDX_I, etc.)
- What type of analysis to run (technical_analysis, swing_scan, options_scan)
- Priority order of analysis tasks

This makes the system truly autonomous - you just ask what you want, and the LLM figures out how to get it.

**Manual Examples (optional):**
If `SHOW_MANUAL_EXAMPLES=true`, it also runs fixed examples for comparison.

# Test File Updates

## Summary

Updated test examples to reflect recent enhancements to DhanHQ tool calling, particularly around historical data and technical indicators.

## Files Updated

### 1. `examples/test_dhanhq_tool_calling.rb`

#### Changes Made:

1. **Updated `historical_data_tool` definition** (lines 66-101):
   - Changed `interval` enum from `["daily", "weekly", "monthly"]` to `["1", "5", "15", "25", "60"]`
   - Added proper description: "Minute interval for intraday data. Omit for daily data."
   - Added `calculate_indicators` boolean parameter
   - Updated description to mention technical indicators (RSI, MACD, SMA, EMA, Bollinger Bands, ATR)
   - Added `required` fields: `from_date` and `to_date`

2. **Added Test 5: Historical Data with Technical Indicators**
   - Tests the new `calculate_indicators` parameter
   - Verifies LLM includes all required parameters including interval
   - Shows how to request intraday data with indicators

3. **Added Test 6: Intraday Data with 5-minute intervals**
   - Tests intraday data specifically
   - Uses current date dynamically
   - Validates interval parameter is one of the valid values (1, 5, 15, 25, 60)
   - Shows date range handling

4. **Enhanced Summary Section**
   - Added notes about historical data enhancements
   - Documents interval usage for intraday vs daily data
   - Explains `calculate_indicators` feature and its benefits

## Key Features Tested

### Intraday Data
- ✅ Interval parameter with values: "1", "5", "15", "25", "60"
- ✅ Date handling (from_date, to_date)
- ✅ 5-minute intervals (most commonly used for intraday analysis)

### Technical Indicators
- ✅ `calculate_indicators` parameter
- ✅ Returns RSI, MACD, SMA, EMA, Bollinger Bands, ATR
- ✅ Reduces response size vs raw OHLCV data

### Tool Calling
- ✅ chat_raw() method for accessing tool_calls
- ✅ Structured Tool classes
- ✅ Parameter validation

## Example Usage

```ruby
# Get intraday data with indicators
historical_data_tool = Ollama::Tool.new(
  type: "function",
  function: Ollama::Tool::Function.new(
    name: "get_historical_data",
    description: "Get historical price data (OHLCV) or technical indicators...",
    parameters: Ollama::Tool::Function::Parameters.new(
      type: "object",
      properties: {
        interval: Ollama::Tool::Function::Parameters::Property.new(
          type: "string",
          description: "Minute interval for intraday data",
          enum: %w[1 5 15 25 60]  # Updated from ["daily", "weekly", "monthly"]
        ),
        calculate_indicators: Ollama::Tool::Function::Parameters::Property.new(
          type: "boolean",
          description: "If true, returns technical indicators instead of raw data"
        ),
        # ... other properties
      }
    )
  )
)

# Request with intraday and indicators
response = client.chat_raw(
  messages: [Ollama::Agent::Messages.user(
    "Get NIFTY intraday data with 5-minute intervals and technical indicators"
  )],
  tools: historical_data_tool
)
```

## Testing

Run the updated tests:

```bash
# Tool calling examples
ruby examples/test_dhanhq_tool_calling.rb
ruby examples/test_tool_calling.rb

# DhanHQ specific tests
ruby examples/dhanhq/test_tool_calling.rb
```

## Notes

- The `interval` parameter is now correctly defined for intraday minute intervals
- The old values ("daily", "weekly", "monthly") were incorrect for the DhanHQ API
- The new `calculate_indicators` parameter provides technical analysis without large response sizes
- Tests now include date handling examples using `Date.today`

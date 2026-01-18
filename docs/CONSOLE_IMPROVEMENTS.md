# Console Improvements

## Overview

Enhanced the interactive console experiences (`chat_console.rb` and `dhan_console.rb`) to provide better user feedback and cleaner output formatting.

## Chat Console (`chat_console.rb`)

### Problem

When the LLM was processing a response, the `llm>` prompt appeared immediately, making it look like it was waiting for user input. This caused confusion where users would start typing, thinking it was a prompt.

### Solution

Added a **thinking indicator** that shows while waiting for the API response:

**Before:**
```
you> Hi
llm> [cursor blinks here - looks like a prompt!]
[user types something]
[then response appears]
```

**After:**
```
you> Hi
... [thinking indicator in cyan]
llm> Hey! How can I help you?
you> [clear prompt for next input]
```

### Implementation

```ruby
def chat_response(client, messages, config)
  content = +""
  prompt_printed = false

  # Show thinking indicator
  print "#{COLOR_LLM}...#{COLOR_RESET}"
  $stdout.flush

  client.chat_raw(...) do |chunk|
    token = chunk.dig("message", "content").to_s
    next if token.empty?

    # Replace thinking indicator with llm> on first token
    unless prompt_printed
      print "\r#{LLM_PROMPT}"
      prompt_printed = true
    end

    content << token
    print token
    $stdout.flush
  end

  puts
  content
end
```

**Key Changes:**
- `\r` (carriage return) replaces `...` with `llm>` when first token arrives
- `$stdout.flush` ensures immediate visual feedback
- Clear visual state: thinking → responding → ready for input

## DhanHQ Console (`dhan_console.rb`)

### Problem

Tool results were displayed as raw JSON dumps, making it hard to quickly understand:
- **Which tool** was called
- **What data** was retrieved
- **Key information** from the response

**Before:**
```
Tool Results:
- get_live_ltp
{
  "action": "get_live_ltp",
  "params": {
    "security_id": "13",
    "symbol": "NIFTY",
    "exchange_segment": "IDX_I"
  },
  "result": {
    "security_id": "13",
    "exchange_segment": "IDX_I",
    "ltp": 25694.35,
    "ltp_data": {
      "last_price": 25694.35
    },
    "symbol": "NIFTY"
  }
}
```

### Solution

Implemented **formatted, human-readable tool results** that extract and display key information:

**After:**
```
🔧 Tool Called: get_live_ltp
   → NIFTY (IDX_I)
   → Last Price: ₹25694.35

llm> The current price of NIFTY is 25694.35.
```

### Formatted Output by Tool

#### 1. Live LTP (`get_live_ltp`)
```
🔧 Tool Called: get_live_ltp
   → NIFTY (IDX_I)
   → Last Price: ₹25694.35
```

#### 2. Market Quote (`get_market_quote`)
```
🔧 Tool Called: get_market_quote
   → RELIANCE
   → LTP: ₹1457.9
   → OHLC: O:1458.8 H:1480.0 L:1455.1 C:1457.9
   → Volume: 17167161
```

#### 3. Historical Data (`get_historical_data`)

**Regular data:**
```
🔧 Tool Called: get_historical_data
   → Historical data: 30 records
   → Interval: 5
```

**With indicators:**
```
🔧 Tool Called: get_historical_data
   → Technical Indicators:
   →   Current Price: ₹25694.35
   →   RSI(14): 56.32
   →   MACD: 12.45
   →   SMA(20): ₹25680.12
   →   SMA(50): ₹25550.45
```

#### 4. Option Chain (`get_option_chain`)
```
🔧 Tool Called: get_option_chain
   → Spot: ₹25694.35
   → Strikes: 15
   → (Filtered: ATM/OTM/ITM with both CE & PE)
```

#### 5. Expiry List (`get_expiry_list`)
```
🔧 Tool Called: get_expiry_list
   → Available expiries: 12
   → Next expiry: 2026-01-20
   → Expiries: 2026-01-20, 2026-01-27, 2026-02-03, 2026-02-10, 2026-02-17...
```

#### 6. Find Instrument (`find_instrument`)
```
🔧 Tool Called: find_instrument
   → Found: NIFTY
   → Security ID: 13
   → Exchange: IDX_I
```

### Implementation

```ruby
def print_formatted_result(tool_name, content)
  result = content.dig("result") || content

  case tool_name
  when "get_live_ltp"
    print_ltp_result(result)
  when "get_market_quote"
    print_quote_result(result)
  when "get_historical_data"
    print_historical_result(result, content)
  # ... other tool formatters
  end
end
```

Each tool has a dedicated formatter that:
1. Extracts key information from the result
2. Formats it in a human-readable way
3. Uses color coding for better readability
4. Shows relevant details without overwhelming the user

## Benefits

### Chat Console
✅ **Clear visual feedback** - Users know when the LLM is thinking vs responding
✅ **No confusion** - Thinking indicator prevents accidental typing
✅ **Better UX** - Immediate response to user input

### DhanHQ Console
✅ **Instant comprehension** - See what tool was called at a glance
✅ **Key data highlighted** - Important values (price, volume) are prominent
✅ **Less noise** - No JSON clutter, just the facts
✅ **Consistent formatting** - Each tool type has predictable output
✅ **Professional appearance** - Clean, organized display with icons

## Configuration

Both consoles support environment variables:

**Chat Console:**
```bash
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.1:8b
OLLAMA_TEMPERATURE=0.7
OLLAMA_SYSTEM="You are a helpful assistant"
```

**DhanHQ Console:**
```bash
# All chat console vars, plus:
DHANHQ_CLIENT_ID=your_client_id
DHANHQ_ACCESS_TOKEN=your_token
SHOW_PLAN=true              # Show planning step
ALLOW_NO_TOOL_OUTPUT=false  # Require tool calls
```

## Testing

```bash
# Test chat console with thinking indicator
ruby examples/chat_console.rb

# Test DhanHQ console with formatted results
ruby examples/dhan_console.rb
```

Try queries like:
- "What is NIFTY price?" → See formatted LTP
- "Get RELIANCE quote" → See formatted quote with OHLC
- "Show me historical data for NIFTY" → See record count
- "Get option chain for NIFTY" → See filtered strikes

## Related Files

- `examples/chat_console.rb` - Simple chat with thinking indicator
- `examples/dhan_console.rb` - Market data with formatted tool results
- `examples/dhanhq_tools.rb` - Underlying DhanHQ tool implementations
- `docs/TESTING.md` - Testing guide

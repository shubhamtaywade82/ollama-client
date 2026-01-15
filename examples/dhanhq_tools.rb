#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Tools - All DhanHQ API operations
# Contains:
# - Data APIs (6): Market Quote, Live Market Feed, Full Market Depth,
#   Historical Data, Expired Options Data, Option Chain
# - Trading Tools: Order parameter building (does not place orders)

require "json"
require "date"
require "dhan_hq"

# Helper to get valid exchange segments from DhanHQ constants
def valid_exchange_segments
  DhanHQ::Constants::EXCHANGE_SEGMENTS
rescue StandardError
  ["NSE_EQ", "NSE_FNO", "NSE_CURRENCY", "BSE_EQ", "BSE_FNO",
   "BSE_CURRENCY", "MCX_COMM", "IDX_I"]
end

# Helper to get INDEX constant
def index_exchange_segment
  DhanHQ::Constants::INDEX
rescue StandardError
  "IDX_I"
end

# Helper to extract values from different data structures
def extract_value(data, keys)
  return nil unless data

  keys.each do |key|
    if data.is_a?(Hash)
      return data[key] if data.key?(key)
    elsif data.respond_to?(key)
      return data.send(key)
    end
  end

  # If data is a simple value and we're looking for it directly
  return data if data.is_a?(Numeric) || data.is_a?(String)

  nil
end

# Helper to safely get instrument attribute (handles missing methods)
def safe_instrument_attr(instrument, attr_name)
  return nil unless instrument

  instrument.respond_to?(attr_name) ? instrument.send(attr_name) : nil
rescue StandardError
  nil
end

# Helper to validate security_id is numeric (integer or numeric string), not a symbol string
# Returns [is_valid, result_or_error_message]
# If valid: [true, integer_value]
# If invalid: [false, error_message_string]
def validate_security_id_numeric(security_id)
  return [false, "security_id cannot be nil"] if security_id.nil?

  # If it's already an integer, it's valid
  return [true, security_id.to_i] if security_id.is_a?(Integer)

  # If it's a string, check if it's numeric
  if security_id.is_a?(String)
    # Remove whitespace
    cleaned = security_id.strip

    # Check if it's a numeric string (all digits, possibly with leading/trailing spaces)
    return [true, cleaned.to_i] if cleaned.match?(/^\d+$/)

    # It's a non-numeric string (likely a symbol like "NIFTY")
    return [false,
            "security_id must be numeric (integer or numeric string like '13'), not a symbol string like '#{cleaned}'. Use symbol parameter for symbols."]

  end

  # Try to convert to integer
  begin
    int_value = security_id.to_i
    # Check if conversion was successful (to_i returns 0 for non-numeric strings)
    if int_value.zero? && security_id.to_s.strip != "0"
      return [false, "security_id must be numeric (integer or numeric string), got: #{security_id.inspect}"]
    end

    [true, int_value]
  rescue StandardError
    [false, "security_id must be numeric (integer or numeric string), got: #{security_id.inspect}"]
  end
end

# Debug logging helper (if needed)
def debug_log(location, message, data = {}, hypothesis_id = nil)
  log_entry = {
    sessionId: "debug-session",
    runId: "run1",
    hypothesisId: hypothesis_id,
    location: location,
    message: message,
    data: data,
    timestamp: Time.now.to_f * 1000
  }
  File.open("/home/nemesis/project/ollama-client/.cursor/debug.log", "a") do |f|
    f.puts(log_entry.to_json)
  end
rescue StandardError
  # Ignore logging errors
end

# DhanHQ Data Tools - Data APIs only
# Contains only the 6 Data APIs:
# 1. Market Quote
# 2. Live Market Feed (LTP)
# 3. Full Market Depth
# 4. Historical Data
# 5. Expired Options Data
# 6. Option Chain
#
# NOTE: These tools are callable functions. For use with Ollama::Agent::Executor,
# you can either:
# 1. Use them directly as callables (auto-inferred schema)
# 2. Wrap them with structured Ollama::Tool classes for explicit schemas
#    See examples/dhanhq/technical_analysis_agentic_runner.rb for examples
#    of structured Tool definitions with type safety and better LLM understanding.
class DhanHQDataTools
  class << self
    # Rate limiting: MarketFeed APIs have a limit of 1 request per second
    # Track last API call time to enforce rate limiting
    @last_marketfeed_call = nil
    @marketfeed_mutex = Mutex.new

    # Helper to enforce rate limiting for MarketFeed APIs (1 request per second)
    def rate_limit_marketfeed
      @marketfeed_mutex ||= Mutex.new
      @marketfeed_mutex.synchronize do
        if @last_marketfeed_call
          elapsed = Time.now - @last_marketfeed_call
          sleep(1.1 - elapsed) if elapsed < 1.1 # Add 0.1s buffer
        end
        @last_marketfeed_call = Time.now
      end
    end

    # 0. Find Instrument - Search for instrument by symbol across common exchange segments
    #
    # REQUIRED PARAMETERS:
    #   - symbol [String]: Trading symbol to search for (e.g., "NIFTY", "RELIANCE", "TCS")
    #
    # Returns: Instrument details including:
    #   - exchange_segment: Exchange and segment identifier (e.g., "IDX_I", "NSE_EQ")
    #   - security_id: Numeric security ID (use this for subsequent API calls)
    #   - trading_symbol: Trading symbol
    #   - instrument_type: Type of instrument (EQUITY, INDEX, etc.)
    #   - name: Full name of the instrument
    #   - isin: ISIN code if available
    #
    # This is useful when you only have a symbol and need to resolve it to proper parameters
    # Searches across common segments: NSE_EQ, BSE_EQ, NSE_FNO, BSE_FNO, IDX_I, NSE_CURRENCY, BSE_CURRENCY, MCX_COMM
    def find_instrument(symbol:)
      unless symbol
        return {
          action: "find_instrument",
          error: "Symbol is required",
          params: { symbol: symbol }
        }
      end

      symbol_str = symbol.to_s.upcase
      common_index_symbols = %w[NIFTY BANKNIFTY FINNIFTY MIDCPNIFTY SENSEX BANKEX]

      if common_index_symbols.include?(symbol_str)
        instrument = DhanHQ::Models::Instrument.find("IDX_I", symbol_str)
        if instrument
          return {
            action: "find_instrument",
            params: { symbol: symbol_str },
            result: {
              symbol: symbol_str,
              exchange_segment: "IDX_I",
              security_id: safe_instrument_attr(instrument, :security_id),
              trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
              instrument_type: safe_instrument_attr(instrument, :instrument_type),
              name: safe_instrument_attr(instrument, :name),
              isin: safe_instrument_attr(instrument, :isin)
            }
          }
        end
      end

      common_segments = %w[NSE_EQ BSE_EQ NSE_FNO BSE_FNO IDX_I NSE_CURRENCY BSE_CURRENCY MCX_COMM]

      common_segments.each do |segment|
        instrument = DhanHQ::Models::Instrument.find(segment, symbol_str)
        next unless instrument

        return {
          action: "find_instrument",
          params: { symbol: symbol_str },
          result: {
            symbol: symbol_str,
            exchange_segment: segment,
            security_id: safe_instrument_attr(instrument, :security_id),
            trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
            instrument_type: safe_instrument_attr(instrument, :instrument_type),
            name: safe_instrument_attr(instrument, :name),
            isin: safe_instrument_attr(instrument, :isin)
          }
        }
      end

      {
        action: "find_instrument",
        error: "Instrument not found in any common exchange segment",
        params: { symbol: symbol_str },
        suggestions: "Try specifying exchange_segment explicitly (NSE_EQ, BSE_EQ, etc.)"
      }
    rescue StandardError => e
      {
        action: "find_instrument",
        error: e.message,
        params: { symbol: symbol }
      }
    end

    # 1. Market Quote API - Get market quote using Instrument convenience method
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment identifier
    #     Valid values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "RELIANCE")
    #     security_id: Numeric security ID
    #
    # Returns: Full market quote with OHLC, depth, volume, and other market data
    #
    # Rate limit: 1 request per second
    # Up to 1000 instruments per request
    #
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    def get_market_quote(exchange_segment:, security_id: nil, symbol: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      # If security_id is provided, we cannot use Instrument.find (which expects symbol)
      # We need symbol to find the instrument, or we need to use security_id directly with MarketFeed API
      unless symbol || security_id
        return {
          action: "get_market_quote",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      # If symbol is provided, find instrument first to get security_id
      if security_id && !symbol
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_market_quote",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_market_quote",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end

        # Use MarketFeed.quote directly with security_id
        payload = { exchange_segment => [security_id_int] }
        quote_response = DhanHQ::Models::MarketFeed.quote(payload)

        if quote_response.is_a?(Hash) && quote_response["data"]
          quote_data = quote_response.dig("data", exchange_segment, security_id_int.to_s)
        end

        return {
          action: "get_market_quote",
          params: { security_id: security_id_int, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: security_id_int,
            exchange_segment: exchange_segment,
            quote: quote_data || quote_response
          }
        }
      end

      # Find instrument using symbol (Instrument.find expects symbol, not security_id)
      instrument_symbol = symbol.to_s
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        # Use instrument convenience method - automatically uses instrument's attributes
        # Returns nested structure: {"data"=>{"NSE_EQ"=>{"2885"=>{...}}}, "status"=>"success"}
        quote_response = instrument.quote

        # Extract actual quote data from nested structure
        security_id_str = safe_instrument_attr(instrument, :security_id)&.to_s || security_id.to_s
        if quote_response.is_a?(Hash) && quote_response["data"]
          quote_data = quote_response.dig("data", exchange_segment,
                                          security_id_str)
        end

        {
          action: "get_market_quote",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: safe_instrument_attr(instrument, :security_id) || security_id,
            symbol: instrument_symbol,
            exchange_segment: exchange_segment,
            quote: quote_data || quote_response
          }
        }
      else
        {
          action: "get_market_quote",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end
    rescue StandardError => e
      {
        action: "get_market_quote",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end

    # 2. Live Market Feed API - Get LTP (Last Traded Price) using Instrument convenience method
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment identifier
    #     Valid values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "RELIANCE")
    #     security_id: Numeric security ID
    #
    # Returns: Last Traded Price (LTP) - fastest API for current price
    #
    # Rate limit: 1 request per second
    # Up to 1000 instruments per request
    #
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    def get_live_ltp(exchange_segment:, security_id: nil, symbol: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return {
          action: "get_live_ltp",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      if security_id && !symbol
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_live_ltp",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_live_ltp",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end

        # Use MarketFeed.ltp directly with security_id
        payload = { exchange_segment => [security_id_int] }
        ltp_response = DhanHQ::Models::MarketFeed.ltp(payload)

        if ltp_response.is_a?(Hash) && ltp_response["data"]
          ltp_data = ltp_response.dig("data", exchange_segment, security_id_int.to_s)
          ltp = extract_value(ltp_data, [:last_price, "last_price"]) if ltp_data
        else
          ltp = extract_value(ltp_response, [:last_price, "last_price", :ltp, "ltp"]) || ltp_response
          ltp_data = ltp_response
        end

        return {
          action: "get_live_ltp",
          params: { security_id: security_id_int, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: security_id_int,
            exchange_segment: exchange_segment,
            ltp: ltp,
            ltp_data: ltp_data
          }
        }
      end

      # Find instrument using symbol (Instrument.find expects symbol, not security_id)
      instrument_symbol = symbol.to_s
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        # Use instrument convenience method - automatically uses instrument's attributes
        # Returns nested structure: {"data"=>{"NSE_EQ"=>{"2885"=>{"last_price"=>1578.1}}}, "status"=>"success"}
        # OR direct value: 1578.1 (after retry/rate limit handling)
        ltp_response = instrument.ltp

        # Extract LTP from nested structure or use direct value
        if ltp_response.is_a?(Hash) && ltp_response["data"]
          security_id_str = safe_instrument_attr(instrument, :security_id)&.to_s || security_id.to_s
          ltp_data = ltp_response.dig("data", exchange_segment, security_id_str)
          ltp = extract_value(ltp_data, [:last_price, "last_price"]) if ltp_data
        elsif ltp_response.is_a?(Numeric)
          ltp = ltp_response
          ltp_data = { last_price: ltp }
        else
          ltp = extract_value(ltp_response, [:last_price, "last_price", :ltp, "ltp"]) || ltp_response
          ltp_data = ltp_response
        end

        {
          action: "get_live_ltp",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: safe_instrument_attr(instrument, :security_id) || security_id,
            symbol: instrument_symbol,
            exchange_segment: exchange_segment,
            ltp: ltp,
            ltp_data: ltp_data
          }
        }
      else
        {
          action: "get_live_ltp",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end
    rescue StandardError => e
      {
        action: "get_live_ltp",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end

    # 3. Full Market Depth API - Get full market depth (bid/ask levels)
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment identifier
    #     Valid values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "RELIANCE")
    #     security_id: Numeric security ID
    #
    # Returns: Full market depth with order book (bid/ask levels), OHLC, volume, OI
    #
    # Rate limit: 1 request per second (uses quote API which has stricter limits)
    # Up to 1000 instruments per request
    #
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_market_depth(exchange_segment:, security_id: nil, symbol: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return {
          action: "get_market_depth",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      if security_id && !symbol
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_market_depth",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_market_depth",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end

        # Use MarketFeed.quote directly with security_id
        payload = { exchange_segment => [security_id_int] }
        quote_response = DhanHQ::Models::MarketFeed.quote(payload)

        if quote_response.is_a?(Hash) && quote_response["data"]
          quote_data = quote_response.dig("data", exchange_segment, security_id_int.to_s)
        end

        depth = extract_value(quote_data, [:depth, "depth"]) if quote_data
        buy_depth = extract_value(depth, [:buy, "buy"]) if depth
        sell_depth = extract_value(depth, [:sell, "sell"]) if depth

        return {
          action: "get_market_depth",
          params: { security_id: security_id_int, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: security_id_int,
            exchange_segment: exchange_segment,
            market_depth: quote_data || quote_response,
            buy_depth: buy_depth,
            sell_depth: sell_depth,
            ltp: quote_data ? extract_value(quote_data, [:last_price, "last_price"]) : nil,
            volume: quote_data ? extract_value(quote_data, [:volume, "volume"]) : nil,
            oi: quote_data ? extract_value(quote_data, [:oi, "oi"]) : nil,
            ohlc: quote_data ? extract_value(quote_data, [:ohlc, "ohlc"]) : nil
          }
        }
      end

      # Find instrument using symbol (Instrument.find expects symbol, not security_id)
      instrument_symbol = symbol.to_s
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        # Use instrument convenience method - automatically uses instrument's attributes
        # Returns nested structure: {"data"=>{"NSE_EQ"=>{"2885"=>{...}}}, "status"=>"success"}
        quote_response = instrument.quote

        # Extract actual quote data from nested structure
        security_id_str = safe_instrument_attr(instrument, :security_id)&.to_s || security_id.to_s
        if quote_response.is_a?(Hash) && quote_response["data"]
          quote_data = quote_response.dig("data", exchange_segment,
                                          security_id_str)
        end

        # Extract market depth (order book) from quote data
        depth = extract_value(quote_data, [:depth, "depth"]) if quote_data
        buy_depth = extract_value(depth, [:buy, "buy"]) if depth
        sell_depth = extract_value(depth, [:sell, "sell"]) if depth

        {
          action: "get_market_depth",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment },
          result: {
            security_id: safe_instrument_attr(instrument, :security_id) || security_id,
            symbol: instrument_symbol,
            exchange_segment: exchange_segment,
            market_depth: quote_data || quote_response,
            # Market depth (order book) - buy and sell sides
            buy_depth: buy_depth,
            sell_depth: sell_depth,
            # Additional quote data
            ltp: quote_data ? extract_value(quote_data, [:last_price, "last_price"]) : nil,
            volume: quote_data ? extract_value(quote_data, [:volume, "volume"]) : nil,
            oi: quote_data ? extract_value(quote_data, [:oi, "oi"]) : nil,
            ohlc: quote_data ? extract_value(quote_data, [:ohlc, "ohlc"]) : nil
          }
        }
      else
        {
          action: "get_market_depth",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end
    rescue StandardError => e
      {
        action: "get_market_depth",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # 4. Historical Data API - Get historical data using HistoricalData class directly
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment identifier
    #     Valid values: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I
    #   - from_date [String]: Start date in YYYY-MM-DD format (e.g., "2024-01-08")
    #   - to_date [String]: End date (non-inclusive) in YYYY-MM-DD format (e.g., "2024-02-08")
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "RELIANCE")
    #     security_id: Numeric security ID
    #
    # OPTIONAL PARAMETERS:
    #   - interval [String]: Minute intervals for intraday data
    #     Valid values: "1", "5", "15", "25", "60"
    #     If provided, returns intraday data; if omitted, returns daily data
    #   - expiry_code [Integer]: Expiry code for derivatives
    #     Valid values: 0 (far month), 1 (near month), 2 (current month)
    #   - instrument [String]: Instrument type
    #     Valid values: EQUITY, INDEX, FUTIDX, FUTSTK, OPTIDX, OPTSTK, FUTCOM, OPTFUT, FUTCUR, OPTCUR
    #     Auto-detected from exchange_segment if not provided
    #
    # Returns: Historical OHLCV data (arrays of open, high, low, close, volume, timestamp)
    #
    # Notes:
    #   - Maximum 90 days of data for intraday requests
    #   - Historical data available for the last 5 years
    #   - to_date is NON-INCLUSIVE (end date is not included in results)
    #
    # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_historical_data(exchange_segment:, from_date:, to_date:, security_id: nil, symbol: nil, interval: nil,
                            expiry_code: nil, instrument: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return {
          action: "get_historical_data",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      # If symbol is provided, find instrument first to get security_id and instrument type
      if security_id && !symbol
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_historical_data",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_historical_data",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        resolved_security_id = security_id_int.to_s
        found_instrument = nil
      else
        # Find instrument using symbol (Instrument.find expects symbol, not security_id)
        instrument_symbol = symbol.to_s
        found_instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)
        unless found_instrument
          return {
            action: "get_historical_data",
            error: "Instrument not found",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end

        # Get security_id from instrument
        resolved_security_id = safe_instrument_attr(found_instrument, :security_id)
        unless resolved_security_id
          return {
            action: "get_historical_data",
            error: "security_id is required and could not be determined from instrument",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        resolved_security_id = resolved_security_id.to_s
      end

      # Determine instrument type if not provided
      # Valid instrument types: INDEX, FUTIDX, OPTIDX, EQUITY, FUTSTK, OPTSTK, FUTCOM, OPTFUT, FUTCUR, OPTCUR
      valid_instruments = %w[INDEX FUTIDX OPTIDX EQUITY FUTSTK OPTSTK FUTCOM OPTFUT FUTCUR OPTCUR]

      # Try to get from instrument object first, validate it
      instrument_type_from_obj = safe_instrument_attr(found_instrument, :instrument_type)
      instrument_type_from_obj = instrument_type_from_obj.to_s.upcase if instrument_type_from_obj
      instrument_type_from_obj = nil unless valid_instruments.include?(instrument_type_from_obj)

      # Determine instrument type if not provided
      resolved_instrument = if found_instrument
                              instrument_type_from_obj || default_instrument_for(exchange_segment)
                            else
                              instrument&.to_s&.upcase || default_instrument_for(exchange_segment)
                            end

      # Final validation - ensure the resolved instrument type is valid
      resolved_instrument = if valid_instruments.include?(resolved_instrument.to_s.upcase)
                              resolved_instrument.to_s.upcase
                            else
                              # Fallback to EQUITY if invalid
                              "EQUITY"
                            end

      if interval
        # Intraday data using HistoricalData.intraday
        # Returns hash with :open, :high, :low, :close, :volume, :timestamp arrays
        intraday_params = {
          security_id: resolved_security_id,
          exchange_segment: exchange_segment,
          instrument: resolved_instrument,
          interval: interval.to_s,
          from_date: from_date,
          to_date: to_date
        }
        intraday_params[:expiry_code] = expiry_code if expiry_code
        data = DhanHQ::Models::HistoricalData.intraday(intraday_params)

        # Count is based on the length of one of the arrays (e.g., :open or :close)
        count = if data.is_a?(Hash)
                  data[:open]&.length || data[:close]&.length || data["open"]&.length || data["close"]&.length || 0
                else
                  0
                end

        {
          action: "get_historical_data",
          type: "intraday",
          params: { security_id: resolved_security_id, symbol: symbol, exchange_segment: exchange_segment,
                    instrument: resolved_instrument, from_date: from_date, to_date: to_date, interval: interval },
          result: {
            data: data,
            count: count,
            instrument_info: {
              security_id: resolved_security_id,
              trading_symbol: safe_instrument_attr(found_instrument, :trading_symbol),
              instrument_type: resolved_instrument
            }
          }
        }
      else
        # Daily data using HistoricalData.daily
        # Returns hash with :open, :high, :low, :close, :volume, :timestamp arrays
        daily_params = {
          security_id: resolved_security_id,
          exchange_segment: exchange_segment,
          instrument: resolved_instrument,
          from_date: from_date,
          to_date: to_date
        }
        daily_params[:expiry_code] = expiry_code if expiry_code
        data = DhanHQ::Models::HistoricalData.daily(daily_params)

        # Count is based on the length of one of the arrays (e.g., :open or :close)
        count = if data.is_a?(Hash)
                  data[:open]&.length || data[:close]&.length || data["open"]&.length || data["close"]&.length || 0
                else
                  0
                end

        {
          action: "get_historical_data",
          type: "daily",
          params: { security_id: resolved_security_id, symbol: symbol, exchange_segment: exchange_segment,
                    instrument: resolved_instrument, from_date: from_date, to_date: to_date, expiry_code: expiry_code },
          result: {
            data: data,
            count: count,
            instrument_info: {
              security_id: resolved_security_id,
              trading_symbol: safe_instrument_attr(found_instrument, :trading_symbol),
              instrument_type: resolved_instrument
            }
          }
        }
      end
    rescue StandardError => e
      {
        action: "get_historical_data",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end

    def default_instrument_for(exchange_segment)
      defaults = {
        "IDX_I" => "INDEX",
        "NSE_FNO" => "FUTIDX",
        "BSE_FNO" => "FUTIDX",
        "NSE_CURRENCY" => "FUTCUR",
        "BSE_CURRENCY" => "FUTCUR",
        "MCX_COMM" => "FUTCOM"
      }

      defaults.fetch(exchange_segment, "EQUITY")
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # 6a. Option Expiry List API - Get list of available expiry dates for an underlying instrument
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment of underlying
    #     For indices (NIFTY, BANKNIFTY): Use "IDX_I"
    #     For stocks: Use "NSE_FNO" or "BSE_FNO"
    #     Valid values: IDX_I (Index), NSE_FNO (NSE F&O), BSE_FNO (BSE F&O), MCX_FO (MCX)
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "BANKNIFTY")
    #     security_id: Numeric security ID of underlying (use value from find_instrument)
    #
    # Returns: Array of available expiry dates in "YYYY-MM-DD" format
    #
    # Rate limit: 1 request per 3 seconds
    #
    # Note: For index options, underlying_seg should be "IDX_I", not "NSE_FNO"
    def get_expiry_list(exchange_segment:, security_id: nil, symbol: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return {
          action: "get_expiry_list",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      if security_id
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_expiry_list",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_expiry_list",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
          }
        end

        underlying_seg = if exchange_segment == "IDX_I"
                           "IDX_I"
                         else
                           exchange_segment
                         end
        resolved_security_id = security_id_int
        found_instrument = nil
      elsif symbol
        instrument_symbol = symbol.to_s
        underlying_seg, found_instrument = find_underlying_instrument(exchange_segment, instrument_symbol)
        resolved_security_id = resolve_security_id_for_option_chain(nil, found_instrument)
      end

      unless resolved_security_id
        return {
          action: "get_expiry_list",
          error: "security_id is required and could not be determined from instrument",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      expiries = DhanHQ::Models::OptionChain.fetch_expiry_list(
        underlying_scrip: resolved_security_id,
        underlying_seg: underlying_seg
      )

      {
        action: "get_expiry_list",
        params: {
          security_id: resolved_security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        }.compact,
        result: {
          expiries: expiries,
          count: expiries.is_a?(Array) ? expiries.length : 0,
          instrument_info: {
            underlying_security_id: resolved_security_id,
            underlying_seg: underlying_seg,
            trading_symbol: found_instrument ? safe_instrument_attr(found_instrument, :trading_symbol) : symbol
          }
        }
      }
    rescue StandardError => e
      {
        action: "get_expiry_list",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end

    # 6. Option Chain API - Get option chain using OptionChain.fetch
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment of underlying
    #     For indices (NIFTY, BANKNIFTY): Use "IDX_I"
    #     For stocks: Use "NSE_FNO" or "BSE_FNO"
    #     Valid values: IDX_I (Index), NSE_FNO (NSE F&O), BSE_FNO (BSE F&O), MCX_FO (MCX)
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol (e.g., "NIFTY", "BANKNIFTY")
    #     security_id: Numeric security ID of underlying (use value from find_instrument)
    #   - expiry [String]: Expiry date in YYYY-MM-DD format (REQUIRED)
    #
    # Returns: Option chain with CE/PE data for all strikes
    #
    # Rate limit: 1 request per 3 seconds
    # Automatically filters out strikes where both CE and PE have zero last_price
    #
    # Note: For index options, underlying_seg should be "IDX_I", not "NSE_FNO"
    # Note: Use get_expiry_list first to get available expiry dates if you don't know the expiry
    # Note: Chain is automatically filtered to show strikes around ATM (default: 5 strikes = 2 ITM, ATM, 2 OTM)
    def get_option_chain(exchange_segment:, security_id: nil, symbol: nil, expiry: nil, strikes_count: 5)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return option_chain_error(
          "Either symbol or security_id must be provided",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        )
      end

      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      # CRITICAL: Prefer security_id over symbol when both are provided, since security_id is more reliable
      if security_id
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return option_chain_error(
            result,
            security_id: security_id,
            symbol: symbol,
            exchange_segment: exchange_segment
          )
        end
        security_id_int = result
        unless security_id_int.positive?
          return option_chain_error(
            "security_id must be a positive integer, got: #{security_id.inspect}",
            security_id: security_id,
            symbol: symbol,
            exchange_segment: exchange_segment
          )
        end

        # For option chain, underlying_seg should be IDX_I for indices, or match exchange_segment
        # For indices like NIFTY (IDX_I), underlying_seg must be IDX_I
        underlying_seg = if exchange_segment == "IDX_I"
                           "IDX_I"
                         else
                           exchange_segment
                         end
        resolved_security_id = security_id_int
        found_instrument = nil
      elsif symbol
        # Find instrument using symbol (Instrument.find expects symbol, not security_id)
        instrument_symbol = symbol.to_s
        underlying_seg, found_instrument = find_underlying_instrument(exchange_segment, instrument_symbol)

        # Get security_id from instrument
        resolved_security_id = resolve_security_id_for_option_chain(nil, found_instrument)
      else
        return option_chain_error(
          "Either symbol or security_id must be provided",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        )
      end

      unless resolved_security_id
        return option_chain_error(
          "security_id is required and could not be determined from instrument",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        )
      end

      # Validate expiry is provided and not empty
      expiry_str = expiry.to_s.strip if expiry
      if expiry_str.nil? || expiry_str.empty?
        return option_chain_error(
          "expiry is required. Use get_expiry_list to get available expiry dates first.",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        )
      end

      option_chain_for_expiry(
        {
          resolved_security_id: resolved_security_id,
          underlying_seg: underlying_seg,
          exchange_segment: exchange_segment,
          symbol: symbol,
          expiry: expiry,
          found_instrument: found_instrument,
          strikes_count: strikes_count
        }
      )
    rescue StandardError => e
      {
        action: "get_option_chain",
        error: e.message,
        params: {
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        }.compact
      }
    end

    def find_underlying_instrument(exchange_segment, instrument_symbol)
      found_instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)
      return [exchange_segment, found_instrument] if found_instrument
      return [exchange_segment, nil] unless %w[NSE_FNO BSE_FNO].include?(exchange_segment)

      fallback_instrument = DhanHQ::Models::Instrument.find("IDX_I", instrument_symbol)
      return ["IDX_I", fallback_instrument] if fallback_instrument

      [exchange_segment, nil]
    end

    def resolve_security_id_for_option_chain(security_id, found_instrument)
      return security_id.to_i if security_id

      safe_instrument_attr(found_instrument, :security_id)&.to_i
    end

    def option_chain_for_expiry(params)
      resolved_security_id = params.fetch(:resolved_security_id)
      underlying_seg = params.fetch(:underlying_seg)
      exchange_segment = params.fetch(:exchange_segment)
      symbol = params.fetch(:symbol)
      expiry = params.fetch(:expiry)
      found_instrument = params[:found_instrument]
      strikes_count = params.fetch(:strikes_count, 5) # Default: 5 strikes (2 ITM, ATM, 2 OTM)

      # Ensure expiry is a string in YYYY-MM-DD format
      expiry_str = expiry.to_s.strip

      # Validate expiry format (basic check)
      unless expiry_str.match?(/^\d{4}-\d{2}-\d{2}$/)
        return option_chain_error(
          "expiry must be in YYYY-MM-DD format, got: #{expiry.inspect}",
          security_id: resolved_security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        )
      end

      # Ensure underlying_scrip is an integer (as per API docs)
      underlying_scrip_int = resolved_security_id.to_i
      unless underlying_scrip_int.positive?
        return option_chain_error(
          "underlying_scrip (security_id) must be a positive integer, got: #{resolved_security_id.inspect}",
          security_id: resolved_security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        )
      end

      # Validate underlying_seg (as per API docs: IDX_I, NSE_FNO, BSE_FNO, MCX_FO)
      valid_underlying_segs = %w[IDX_I NSE_FNO BSE_FNO MCX_FO]
      unless valid_underlying_segs.include?(underlying_seg)
        return option_chain_error(
          "underlying_seg must be one of: #{valid_underlying_segs.join(', ')}, got: #{underlying_seg.inspect}",
          security_id: resolved_security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        )
      end

      chain = DhanHQ::Models::OptionChain.fetch(
        underlying_scrip: underlying_scrip_int,
        underlying_seg: underlying_seg,
        expiry: expiry_str
      )

      # Extract last_price and filter chain to only relevant strikes around ATM
      last_price = chain[:last_price] || chain["last_price"]
      full_chain = chain[:oc] || chain["oc"] || {}

      # Filter chain to include strikes around ATM (default: 5 strikes = 2 ITM, ATM, 2 OTM)
      filtered_chain = filter_option_chain(full_chain, last_price, strikes_count)

      {
        action: "get_option_chain",
        params: option_chain_params(
          resolved_security_id: resolved_security_id,
          exchange_segment: exchange_segment,
          symbol: symbol,
          expiry: expiry
        ),
        result: {
          expiry: expiry,
          underlying_last_price: last_price,
          chain: filtered_chain,
          chain_count: filtered_chain.is_a?(Hash) ? filtered_chain.keys.length : 0,
          note: "Chain filtered to show #{strikes_count} strikes around ATM (ITM, ATM, OTM)",
          instrument_info: option_chain_instrument_info(
            resolved_security_id: resolved_security_id,
            underlying_seg: underlying_seg,
            found_instrument: found_instrument,
            symbol: symbol
          )
        }
      }
    end

    def option_chain_expiry_list(resolved_security_id:, underlying_seg:, exchange_segment:, symbol:, found_instrument:)
      expiries = DhanHQ::Models::OptionChain.fetch_expiry_list(
        underlying_scrip: resolved_security_id,
        underlying_seg: underlying_seg
      )

      {
        action: "get_option_chain",
        params: option_chain_params(
          resolved_security_id: resolved_security_id,
          exchange_segment: exchange_segment,
          symbol: symbol
        ),
        result: {
          expiries: expiries,
          count: expiries.is_a?(Array) ? expiries.length : 0,
          instrument_info: option_chain_instrument_info(
            resolved_security_id: resolved_security_id,
            underlying_seg: underlying_seg,
            found_instrument: found_instrument,
            symbol: symbol
          )
        }
      }
    end

    def filter_option_chain(full_chain, last_price, strikes_count = 5)
      return {} unless full_chain.is_a?(Hash) && last_price

      last_price_float = last_price.to_f
      return {} if last_price_float.zero?

      # Extract all strike prices that have both CE and PE data
      strikes = full_chain.keys.map do |strike_key|
        strike_data = full_chain[strike_key]
        next unless strike_data.is_a?(Hash)

        # Check if strike has both CE and PE
        has_ce = strike_data.key?(:ce) || strike_data.key?("ce")
        has_pe = strike_data.key?(:pe) || strike_data.key?("pe")
        next unless has_ce && has_pe

        strike_float = strike_key.to_f
        [strike_key, strike_float] if strike_float.positive?
      end.compact

      return {} if strikes.empty?

      # Sort strikes by price
      strikes.sort_by! { |_, price| price }

      # Find ATM strike (closest to last_price)
      atm_strike = strikes.min_by { |_, price| (price - last_price_float).abs }
      return {} unless atm_strike

      atm_index = strikes.index(atm_strike)
      return {} unless atm_index

      # Calculate how many strikes to get on each side of ATM
      # Default: 5 strikes = 2 ITM, ATM, 2 OTM
      # For odd numbers: distribute evenly (e.g., 5 = 2 ITM + ATM + 2 OTM)
      # For even numbers: prefer OTM (e.g., 6 = 2 ITM + ATM + 3 OTM)
      total_strikes = [strikes_count.to_i, 1].max # At least 1 (ATM)
      itm_count = (total_strikes - 1) / 2 # Rounds down for odd, up for even
      otm_count = total_strikes - 1 - itm_count # Remaining after ATM

      selected_strikes = []

      # Get ITM strikes (below ATM)
      itm_start = [atm_index - itm_count, 0].max
      itm_start.upto(atm_index - 1) do |i|
        selected_strikes << strikes[i][0] if strikes[i]
      end

      # ATM
      selected_strikes << atm_strike[0]

      # Get OTM strikes (above ATM)
      otm_end = [atm_index + otm_count, strikes.length - 1].min
      (atm_index + 1).upto(otm_end) do |i|
        selected_strikes << strikes[i][0] if strikes[i]
      end

      # Filter chain to only include selected strikes
      filtered = {}
      selected_strikes.each do |strike_key|
        filtered[strike_key] = full_chain[strike_key] if full_chain.key?(strike_key)
      end

      filtered
    end

    def option_chain_instrument_info(resolved_security_id:, underlying_seg:, found_instrument:, symbol:)
      {
        underlying_security_id: resolved_security_id,
        underlying_seg: underlying_seg,
        trading_symbol: found_instrument ? safe_instrument_attr(found_instrument, :trading_symbol) : symbol
      }
    end

    def option_chain_params(resolved_security_id:, exchange_segment:, symbol:, expiry: nil)
      {
        security_id: resolved_security_id,
        symbol: symbol,
        exchange_segment: exchange_segment,
        expiry: expiry
      }.compact
    end

    def option_chain_error(message, security_id:, symbol:, exchange_segment:, expiry: nil)
      {
        action: "get_option_chain",
        error: message,
        params: {
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment,
          expiry: expiry
        }.compact
      }
    end

    # 5. Expired Options Data API - Get historical expired options data using ExpiredOptionsData.fetch
    #
    # REQUIRED PARAMETERS:
    #   - exchange_segment [String]: Exchange and segment identifier
    #     Valid values: NSE_FNO, BSE_FNO, NSE_EQ, BSE_EQ
    #   - expiry_date [String]: Expiry date in YYYY-MM-DD format
    #   - symbol [String] OR security_id [Integer]: Must provide one
    #     symbol: Trading symbol of underlying
    #     security_id: Numeric security ID of underlying
    #
    # OPTIONAL PARAMETERS (with defaults):
    #   - interval [String]: Minute intervals for timeframe (default: "1")
    #     Valid values: "1", "5", "15", "25", "60"
    #   - instrument [String]: Instrument type (default: auto-detected)
    #     Valid values: "OPTIDX" (Index Options), "OPTSTK" (Stock Options)
    #     Default: "OPTIDX" for IDX_I, "OPTSTK" for others
    #   - expiry_flag [String]: Expiry interval (default: "MONTH")
    #     Valid values: "WEEK", "MONTH"
    #   - expiry_code [Integer]: Expiry code (default: 1 - near month)
    #     Valid values: 0 (far month), 1 (near month), 2 (current month)
    #   - strike [String]: Strike price specification (default: "ATM")
    #     Format: "ATM" for At The Money, "ATM+X" or "ATM-X" for offset strikes
    #     For Index Options (near expiry): Up to ATM+10 / ATM-10
    #     For all other contracts: Up to ATM+3 / ATM-3
    #   - drv_option_type [String]: Option type (default: "CALL")
    #     Valid values: "CALL", "PUT"
    #   - required_data [Array<String>]: Array of required data fields (default: all fields)
    #     Valid values: "open", "high", "low", "close", "iv", "volume", "strike", "oi", "spot"
    #
    # Returns: Historical expired options data organized by strike price relative to spot
    #
    # Notes:
    #   - Up to 31 days of data can be fetched in a single request
    #   - Historical data available for up to the last 5 years
    #   - Data is organized by strike price relative to spot
    #   - from_date is calculated from expiry_date, to_date is expiry_date + 1 day
    #
    # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_expired_options_data(exchange_segment:, expiry_date:, security_id: nil, symbol: nil, expiry_code: nil,
                                 interval: "1", instrument: nil, expiry_flag: "MONTH", strike: "ATM",
                                 drv_option_type: "CALL", required_data: nil)
      # CRITICAL: security_id must be an integer, not a symbol string
      unless symbol || security_id
        return {
          action: "get_expired_options_data",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                    expiry_date: expiry_date }
        }
      end

      exchange_segment = exchange_segment.to_s

      # If security_id is provided, use it directly - it must be numeric (integer or numeric string), not a symbol
      if security_id && !symbol
        is_valid, result = validate_security_id_numeric(security_id)
        unless is_valid
          return {
            action: "get_expired_options_data",
            error: result,
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      expiry_date: expiry_date }
          }
        end
        security_id_int = result
        unless security_id_int.positive?
          return {
            action: "get_expired_options_data",
            error: "security_id must be a positive integer, got: #{security_id.inspect}",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      expiry_date: expiry_date }
          }
        end
        resolved_security_id = security_id_int
        found_instrument = nil
      else
        # Find instrument using symbol (Instrument.find expects symbol, not security_id)
        instrument_symbol = symbol.to_s
        # Try original exchange_segment first, then try IDX_I for indices
        found_instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)
        # If not found and exchange_segment is NSE_FNO/BSE_FNO, try IDX_I for index options
        if !found_instrument && %w[NSE_FNO BSE_FNO].include?(exchange_segment)
          found_instrument = DhanHQ::Models::Instrument.find("IDX_I", instrument_symbol)
        end

        unless found_instrument
          return {
            action: "get_expired_options_data",
            error: "Instrument not found. For options, you may need to provide security_id directly.",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      expiry_date: expiry_date }
          }
        end

        # Get security_id from instrument
        resolved_security_id = safe_instrument_attr(found_instrument, :security_id)
        unless resolved_security_id
          return {
            action: "get_expired_options_data",
            error: "security_id is required and could not be determined from instrument",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      expiry_date: expiry_date }
          }
        end
        resolved_security_id = resolved_security_id.to_i
      end

      # Determine instrument type - must be OPTIDX or OPTSTK
      resolved_instrument = instrument || safe_instrument_attr(found_instrument, :instrument_type)
      resolved_instrument = resolved_instrument.to_s.upcase if resolved_instrument

      # Validate and set default instrument type
      unless %w[OPTIDX OPTSTK].include?(resolved_instrument)
        # Default to OPTIDX for index options (IDX_I), OPTSTK for others
        resolved_instrument = if exchange_segment == "IDX_I"
                                "OPTIDX"
                              else
                                "OPTSTK"
                              end
      end

      # Set default required_data if not provided
      resolved_required_data = required_data || %w[open high low close volume iv oi strike spot]

      # expiry_code is required - use provided value or default to 1 (near month)
      # Valid values: 0 (far month), 1 (near month), 2 (current month)
      # Must be explicitly set, cannot be nil
      resolved_expiry_code = if expiry_code.nil?
                               1 # Default to near month
                             else
                               expiry_code.to_i
                             end

      # Ensure expiry_code is within valid range
      unless [0, 1, 2].include?(resolved_expiry_code)
        resolved_expiry_code = 1 # Fallback to near month if invalid
      end

      # Calculate to_date (expiry_date + 1 day, or same day if single day range)
      from_date_str = expiry_date.to_s
      to_date_obj = Date.parse(from_date_str) + 1
      to_date_str = to_date_obj.strftime("%Y-%m-%d")

      # Call ExpiredOptionsData.fetch with all required parameters
      expired_data = DhanHQ::Models::ExpiredOptionsData.fetch(
        exchange_segment: exchange_segment,
        interval: interval.to_s,
        security_id: resolved_security_id,
        instrument: resolved_instrument,
        expiry_flag: expiry_flag.to_s.upcase,
        expiry_code: resolved_expiry_code.to_i,
        strike: strike.to_s.upcase,
        drv_option_type: drv_option_type.to_s.upcase,
        required_data: resolved_required_data,
        from_date: from_date_str,
        to_date: to_date_str
      )

      {
        action: "get_expired_options_data",
        params: { security_id: resolved_security_id, symbol: symbol, exchange_segment: exchange_segment,
                  expiry_date: expiry_date, expiry_code: resolved_expiry_code, interval: interval,
                  instrument: resolved_instrument, expiry_flag: expiry_flag, strike: strike,
                  drv_option_type: drv_option_type },
        result: {
          security_id: resolved_security_id,
          exchange_segment: exchange_segment,
          expiry_date: expiry_date,
          data: expired_data.data,
          call_data: expired_data.call_data,
          put_data: expired_data.put_data,
          ohlc_data: expired_data.ohlc_data,
          volume_data: expired_data.volume_data,
          summary_stats: expired_data.summary_stats,
          instrument_info: {
            trading_symbol: found_instrument ? safe_instrument_attr(found_instrument, :trading_symbol) : symbol,
            instrument_type: resolved_instrument
          }
        }
      }
    rescue StandardError => e
      {
        action: "get_expired_options_data",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                  expiry_date: expiry_date }
      }
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  end
end

# DhanHQ Trading Tools - Order parameter building only
class DhanHQTradingTools
  class << self
    # Build order parameters (does not place order)
    def build_order_params(params)
      {
        action: "place_order",
        params: params,
        order_params: {
          transaction_type: params[:transaction_type] || "BUY",
          exchange_segment: params[:exchange_segment] || "NSE_EQ",
          product_type: params[:product_type] || "MARGIN",
          order_type: params[:order_type] || "LIMIT",
          validity: params[:validity] || "DAY",
          security_id: params[:security_id],
          quantity: params[:quantity] || 1,
          price: params[:price]
        },
        message: "Order parameters ready: #{params[:transaction_type]} " \
                 "#{params[:quantity]} #{params[:security_id]} @ #{params[:price]}"
      }
    end

    # Build super order parameters (does not place order)
    def build_super_order_params(params)
      {
        action: "place_super_order",
        params: params,
        order_params: {
          transaction_type: params[:transaction_type] || "BUY",
          exchange_segment: params[:exchange_segment] || "NSE_EQ",
          product_type: params[:product_type] || "MARGIN",
          order_type: params[:order_type] || "LIMIT",
          security_id: params[:security_id],
          quantity: params[:quantity] || 1,
          price: params[:price],
          target_price: params[:target_price],
          stop_loss_price: params[:stop_loss_price],
          trailing_jump: params[:trailing_jump] || 10
        },
        message: "Super order parameters ready: Entry @ #{params[:price]}, " \
                 "SL: #{params[:stop_loss_price]}, TP: #{params[:target_price]}"
      }
    end

    # Build cancel order parameters (does not cancel)
    def build_cancel_params(order_id:)
      {
        action: "cancel_order",
        params: { order_id: order_id },
        message: "Cancel parameters ready for order: #{order_id}",
        note: "To actually cancel, call: DhanHQ::Models::Order.find(order_id).cancel"
      }
    end
  end
end


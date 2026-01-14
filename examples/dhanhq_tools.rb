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

    # 1. Market Quote API - Get market quote using Instrument convenience method
    # Uses instrument.quote which automatically uses instrument's security_id,
    # exchange_segment, and instrument attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol
    # (e.g., "NIFTY", "RELIANCE"), not security_id
    # Rate limit: 1 request per second
    def get_market_quote(exchange_segment:, security_id: nil, symbol: nil)
      # Instrument.find expects symbol, support both for backward compatibility
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_market_quote",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      # Find instrument first
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
    # Uses instrument.ltp which automatically uses instrument's security_id, exchange_segment, and instrument attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    # Rate limit: 1 request per second
    def get_live_ltp(exchange_segment:, security_id: nil, symbol: nil)
      # Instrument.find expects symbol, support both for backward compatibility
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_live_ltp",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      # Find instrument first
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
    # Uses instrument.quote which automatically uses instrument's security_id,
    # exchange_segment, and instrument attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol
    # (e.g., "NIFTY", "RELIANCE"), not security_id
    # Rate limit: 1 request per second (uses quote API which has stricter limits)
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_market_depth(exchange_segment:, security_id: nil, symbol: nil)
      # Instrument.find expects symbol, support both for backward compatibility
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_market_depth",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      rate_limit_marketfeed # Enforce rate limiting
      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      # Find instrument first
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
    # Requires: security_id, exchange_segment, instrument (type), from_date, to_date
    # Optional: interval (for intraday), expiry_code (for futures/options)
    # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_historical_data(exchange_segment:, from_date:, to_date:, security_id: nil, symbol: nil, interval: nil,
                            expiry_code: nil, instrument: nil)
      # Need security_id - get it from instrument if we only have symbol
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_historical_data",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      # Find instrument to get security_id and instrument type if not provided
      found_instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)
      unless found_instrument
        return {
          action: "get_historical_data",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      # Get security_id from instrument if not provided
      resolved_security_id = security_id || safe_instrument_attr(found_instrument, :security_id)
      unless resolved_security_id
        return {
          action: "get_historical_data",
          error: "security_id is required and could not be determined from instrument",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      # Determine instrument type if not provided
      # Valid instrument types: INDEX, FUTIDX, OPTIDX, EQUITY, FUTSTK, OPTSTK, FUTCOM, OPTFUT, FUTCUR, OPTCUR
      valid_instruments = %w[INDEX FUTIDX OPTIDX EQUITY FUTSTK OPTSTK FUTCOM OPTFUT FUTCUR OPTCUR]

      # Try to get from instrument object first, validate it
      instrument_type_from_obj = safe_instrument_attr(found_instrument, :instrument_type)
      instrument_type_from_obj = instrument_type_from_obj.to_s.upcase if instrument_type_from_obj
      instrument_type_from_obj = nil unless valid_instruments.include?(instrument_type_from_obj)

      # Use provided instrument, or validated instrument from object, or map from exchange_segment
      resolved_instrument = instrument&.to_s&.upcase ||
                            instrument_type_from_obj ||
                            default_instrument_for(exchange_segment)

      # Final validation - ensure the resolved instrument type is valid
      resolved_instrument = if valid_instruments.include?(resolved_instrument.to_s.upcase)
                              resolved_instrument.to_s.upcase
                            else
                              # Fallback to EQUITY if invalid
                              "EQUITY"
                            end

      resolved_security_id = resolved_security_id.to_s

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

    # 6. Option Chain API - Get option chain using OptionChain.fetch
    # Requires: underlying_scrip (security_id), underlying_seg (exchange_segment), expiry (optional)
    # Note: For index options, underlying_seg should be "IDX_I", not "NSE_FNO"
    def get_option_chain(exchange_segment:, security_id: nil, symbol: nil, expiry: nil)
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return option_chain_error(
          "Either symbol or security_id must be provided",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        )
      end

      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      underlying_seg, found_instrument = find_underlying_instrument(exchange_segment, instrument_symbol)

      # Get security_id from instrument if not provided
      resolved_security_id = resolve_security_id_for_option_chain(security_id, found_instrument)

      unless resolved_security_id
        return option_chain_error(
          "security_id is required and could not be determined from instrument",
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        )
      end

      if expiry
        return option_chain_for_expiry(
          {
            resolved_security_id: resolved_security_id,
            underlying_seg: underlying_seg,
            exchange_segment: exchange_segment,
            symbol: symbol,
            expiry: expiry,
            found_instrument: found_instrument
          }
        )
      end

      option_chain_expiry_list(
        resolved_security_id: resolved_security_id,
        underlying_seg: underlying_seg,
        exchange_segment: exchange_segment,
        symbol: symbol,
        found_instrument: found_instrument
      )
    rescue StandardError => e
      {
        action: "get_option_chain",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
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

      chain = DhanHQ::Models::OptionChain.fetch(
        underlying_scrip: resolved_security_id,
        underlying_seg: underlying_seg,
        expiry: expiry.to_s
      )

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
          underlying_last_price: chain[:last_price],
          chain: chain[:oc],
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

    def option_chain_error(message, security_id:, symbol:, exchange_segment:)
      {
        action: "get_option_chain",
        error: message,
        params: {
          security_id: security_id,
          symbol: symbol,
          exchange_segment: exchange_segment
        }
      }
    end

    # 5. Expired Options Data API - Get historical expired options data using ExpiredOptionsData.fetch
    # Requires: exchange_segment, interval, security_id, instrument (OPTIDX/OPTSTK), expiry_flag, expiry_code,
    #           strike, drv_option_type, required_data, from_date, to_date
    # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def get_expired_options_data(exchange_segment:, expiry_date:, security_id: nil, symbol: nil, expiry_code: nil,
                                 interval: "1", instrument: nil, expiry_flag: "MONTH", strike: "ATM",
                                 drv_option_type: "CALL", required_data: nil)
      # Need security_id - get it from instrument if we only have symbol
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_expired_options_data",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                    expiry_date: expiry_date }
        }
      end

      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s

      # If security_id is provided directly, use it; otherwise find instrument
      if security_id
        resolved_security_id = security_id.to_s
        found_instrument = nil # Don't need to find instrument if we have security_id
      else
        # Find instrument to get security_id - try original exchange_segment first, then try IDX_I for indices
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
        resolved_security_id = resolved_security_id.to_s
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
        security_id: resolved_security_id.to_i,
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


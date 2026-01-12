#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Tools - All DhanHQ API operations
# Contains:
# - Data APIs (6): Market Quote, Live Market Feed, Full Market Depth,
#   Historical Data, Expired Options Data, Option Chain
# - Trading Tools: Order parameter building (does not place orders)

require "json"
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

    # 4. Historical Data API - Get historical data using Instrument convenience methods
    # These methods automatically use instrument's security_id, exchange_segment, and instrument attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    # rubocop:disable Metrics/ParameterLists
    def get_historical_data(exchange_segment:, from_date:, to_date:, security_id: nil, symbol: nil, interval: nil,
                            expiry_code: nil)
      # Instrument.find expects symbol, support both for backward compatibility
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
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        if interval
          # Intraday data - automatically uses instrument's attributes
          data = instrument.intraday(
            from_date: from_date,
            to_date: to_date,
            interval: interval
          )
          {
            action: "get_historical_data",
            type: "intraday",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      from_date: from_date, to_date: to_date, interval: interval },
            result: {
              data: data,
              count: data.is_a?(Array) ? data.length : 0,
              instrument_info: {
                trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
                instrument_type: safe_instrument_attr(instrument, :instrument_type)
              }
            }
          }
        else
          # Daily data - automatically uses instrument's attributes
          # expiry_code is optional for futures/options
          daily_params = { from_date: from_date, to_date: to_date }
          daily_params[:expiry_code] = expiry_code if expiry_code
          data = instrument.daily(**daily_params)
          {
            action: "get_historical_data",
            type: "daily",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                      from_date: from_date, to_date: to_date, expiry_code: expiry_code },
            result: {
              data: data,
              count: data.is_a?(Array) ? data.length : 0,
              instrument_info: {
                trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
                instrument_type: safe_instrument_attr(instrument, :instrument_type)
              }
            }
          }
        end
      else
        {
          action: "get_historical_data",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end
    rescue StandardError => e
      {
        action: "get_historical_data",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end
    # rubocop:enable Metrics/ParameterLists

    # 6. Option Chain API - Get option chain using Instrument convenience methods
    # These methods automatically use instrument's security_id, exchange_segment, and instrument attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    def get_option_chain(exchange_segment:, security_id: nil, symbol: nil, expiry: nil)
      # Instrument.find expects symbol, support both for backward compatibility
      instrument_symbol = symbol || security_id
      unless instrument_symbol
        return {
          action: "get_option_chain",
          error: "Either symbol or security_id must be provided",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end

      instrument_symbol = instrument_symbol.to_s
      exchange_segment = exchange_segment.to_s
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        if expiry
          # Get option chain for specific expiry - automatically uses instrument's attributes
          chain = instrument.option_chain(expiry: expiry)
          {
            action: "get_option_chain",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment, expiry: expiry },
            result: {
              expiry: expiry,
              chain: chain,
              instrument_info: {
                trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
                instrument_type: safe_instrument_attr(instrument, :instrument_type)
              }
            }
          }
        else
          # Get list of available expiries - automatically uses instrument's attributes
          expiries = instrument.expiry_list
          {
            action: "get_option_chain",
            params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment },
            result: {
              expiries: expiries,
              count: expiries.is_a?(Array) ? expiries.length : 0,
              instrument_info: {
                trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
                instrument_type: safe_instrument_attr(instrument, :instrument_type)
              }
            }
          }
        end
      else
        {
          action: "get_option_chain",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
        }
      end
    rescue StandardError => e
      {
        action: "get_option_chain",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment }
      }
    end

    # 5. Expired Options Data API - Get historical expired options data
    # Uses Instrument convenience method which automatically uses instrument's attributes
    # Note: Instrument.find(exchange_segment, symbol) expects symbol (e.g., "NIFTY", "RELIANCE"), not security_id
    def get_expired_options_data(exchange_segment:, expiry_date:, security_id: nil, symbol: nil, expiry_code: nil)
      # Instrument.find expects symbol, support both for backward compatibility
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
      instrument = DhanHQ::Models::Instrument.find(exchange_segment, instrument_symbol)

      if instrument
        # Get historical data for the expiry date - automatically uses instrument's attributes
        daily_params = { from_date: expiry_date, to_date: expiry_date }
        daily_params[:expiry_code] = expiry_code if expiry_code
        expired_data = instrument.daily(**daily_params)
        {
          action: "get_expired_options_data",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                    expiry_date: expiry_date, expiry_code: expiry_code },
          result: {
            security_id: security_id,
            exchange_segment: exchange_segment,
            expiry_date: expiry_date,
            data: expired_data,
            instrument_info: {
              trading_symbol: safe_instrument_attr(instrument, :trading_symbol),
              instrument_type: safe_instrument_attr(instrument, :instrument_type),
              expiry_flag: safe_instrument_attr(instrument, :expiry_flag)
            }
          }
        }
      else
        {
          action: "get_expired_options_data",
          error: "Instrument not found",
          params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                    expiry_date: expiry_date }
        }
      end
    rescue StandardError => e
      {
        action: "get_expired_options_data",
        error: e.message,
        params: { security_id: security_id, symbol: symbol, exchange_segment: exchange_segment,
                  expiry_date: expiry_date }
      }
    end
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


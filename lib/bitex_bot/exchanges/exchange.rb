module BitexBot
  module Exchanges
    Transaction = Struct.new(
      :id,        # String
      :price,     # Decimal
      :amount,    # Decimal
      :timestamp, # Epoch Integer
      :raw        # Actual transaction
    )

    Order = Struct.new(
      :id,        # String
      :type,      # Symbol <:bid|:ask|:undefined>
      :price,     # Decimal
      :amount,    # Decimal
      :timestamp, # Integer
      :status,    # Symbol <:executing|:completed|:cancelled|:undefined>
      :raw        # Actual order object
    )

    Orderbook = Struct.new(
      :timestamp, # Integer
      :bids,      # [OrderSummary]
      :asks       # [OrderSummary]
    )

    OrderSummary = Struct.new(
      :price, # Decimal
      :amount # Decimal # TODO amount instead of quantity
    )

    BalanceSummary = Struct.new(
      :crypto, # Balance
      :fiat,   # Balance
      :fee     # Decimal
    )

    Balance = Struct.new(
      :total,    # Decimal
      :reserved, # Decimal
      :available # Decimal
    )

    UserTransaction = Struct.new(
      :order_id,    # Integer
      :fiat,        # Decimal
      :crypto,      # Decimal
      :price,       # Decimal
      :fee,         # Decimal
      :type,        # String <:buy|:sell> # TODO On Bitstamp can't retrive trade type in a simple request.
      :timestamp,   # Epoch Integer
      :raw
    )

    # General behaviour for trading platform wrappers.
    class Exchange
      attr_accessor :currency_pair

      MIN_AMOUNT = 10.to_d

      def base_quote
        @base_quote ||= "#{base}_#{quote}".freeze
      end

      def base
        @base ||= currency_pair.base.to_s.upcase.freeze
      end

      def quote
        @quote ||= currency_pair.quote.to_s.upcase.freeze
      end

      # Respond to minimun order size to place order.
      #
      # @param [BigDecimal] amount.
      # @param [BigDecimal] price.
      #
      # @return [Boolean]
      def enough_order_size?(amount, price, _trade_type = nil)
        amount * price >= MIN_AMOUNT
      end

      # @param [Symbol] trade_type. <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount. Crypto amount.
      #
      # @hooks :send_order, :find_lost
      #
      # @return [Order|OrderNotFound]
      def place_order(trade_type, price, amount) # rubocop:disable Metrics/AbcSize
        threshold = 1.minute.ago.utc
        order = send_order(trade_type, price, amount)
        return order unless order.nil? || order.try(:id).nil?

        # Order may have gone through and be stuck somewhere in Wrapper's pipeline.
        # We just sleep for a bit and then look for the order.
        5.times do |i|
          Robot.log(
            :info,
            :wrapper,
            :look_lost,
            "#{self.class} cauldn't place #{trade_type} order #{i} times for #{base.upcase} "\
            "#{amount.truncate(8)} @ #{quote.upcase} #{price.truncate(8)}"
          )

          Robot.sleep_for(10)
          order = find_lost(trade_type, price, amount, threshold)
          return order if order.present?
        end

        raise OrderNotFound, "Not found #{trade_type} order for #{base} #{amount} @ #{quote} #{price}."
      end

      # @return [BalanceSummary]
      def balance
        raise 'self subclass responsibility'
      end

      # @return [Orderbook]
      def market(_retries = 20)
        raise 'self subclass responsibility'
      end

      # @return [Array<Order>]
      def orders
        raise 'self subclass responsibility'
      end

      # @return [nil]
      def cancel_order(_order)
        raise 'self subclass responsibility'
      end

      # @return [Array<Transaction>]
      def transactions
        raise 'self subclass responsibility'
      end

      # @return [Array<UserTransaction>]
      def user_transactions
        raise 'self subclass responsibility'
      end

      # @param [String] order_id.
      #   Returns involved fiat and cryptos on trade for order_id.
      #
      # @returns [Array<BigDecimal, BigDecimal>]
      def amount_and_quantity(_order_id)
        raise 'self subclass responsibility'
      end
    end

    class OrderNotFound < StandardError; end
    class OrderError < StandardError; end
  end
end

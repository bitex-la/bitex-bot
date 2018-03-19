##
# This class represents the general behaviour for trading platform wrappers.
#
class ApiWrapper
  MIN_AMOUNT = 5

  Transaction = Struct.new(
    :id, # Integer
    :price, # Decimal
    :amount, # Decimal
    :timestamp # Integer Epoch
  )

  Order = Struct.new(
    :id, # String
    :type, # Symbol
    :price, # Decimal
    :amount, # Decimal
    :timestamp, # Integer
    :order # Actual order object
  ) do
    def method_missing(method_name, *args, &_block)
      order.send(method_name, *args) || super
    end

    def respond_to_missing?(method_name, include_private = false)
      respond_to_custom_methods?(method_name) || super
    end

    def respond_to_custom_methods?(method_name)
      %i[cancel!].include?(method_name)
    end
  end

  OrderBook = Struct.new(
    :timestamp, # Integer
    :bids, # [OrderSummary]
    :asks # [OrderSummary]
  )

  OrderSummary = Struct.new(
    :price, # Decimal
    :quantity # Decimal
  )

  BalanceSummary = Struct.new(
    :btc, # Balance
    :usd, # Balance
    :fee # Decimal
  )

  Balance = Struct.new(
    :total, # Decimal
    :reserved, # Decimal
    :available # Decimal
  )

  UserTransaction = Struct.new(
    :order_id, # Integer
    :usd, # Decimal
    :btc, # Decimal,
    :btc_usd, # Decimal
    :fee, # Decimal,
    :type, # Integer
    :timestamp # Integer Epoch
  )

  class << self
    # @return [Void]
    def setup(_settings)
      raise 'self subclass responsibility'
    end

    # @return [Array<Transaction>]
    def transactions
      raise 'self subclass responsibility'
    end

    # @return [OrderBook]
    def order_book(_retries = 20)
      raise 'self subclass responsibility'
    end

    # @return [BalanceSummary]
    def balance
      raise 'self subclass responsibility'
    end

    # @return [nil]
    def cancel
      raise 'self subclass responsibility'
    end

    # @return [Array<Order>]
    def orders
      raise 'self subclass responsibility'
    end

    # @return [UserTransaction]
    def user_transacitions
      raise 'self subclass responsibility'
    end

    # @param type
    # @param price
    # @param quantity
    def place_order(type, price, quantity)
      order = send_order(type, price, quantity)
      return order unless order.nil? || order.id.nil?
      BitexBot::Robot.logger.debug("Captured error when placing order on #{self.class.name}")

      # Order may have gone through and be stuck somewhere in Wrapper's piipeline.
      # We just sleep for a bit and then look for the order.
      20.times do
        BitexBot::Robot.sleep_for(10)
        order = find_lost(type, price, quantity)
        return order if order.present?
      end

      raise OrderNotFound, "Closing: #{type} order not found for #{quantity} BTC @ $#{price}. #{order}"
    end

    # Hook Method - thearguments could not be used in their entirety by the subclasses
    def send_order(_type, _price, _quantity)
      raise 'self subclass responsibility'
    end

    # @param order_method [String] buy|sell
    # @param price [Decimal]
    #
    # Hook Method - the arguments could not be used in their entirety by the subclasses
    def find_lost(_type, _price, _quantity)
      raise 'self subclass responsibility'
    end

    # @param order_id
    # @param transactions
    # @return [Array<Decimal, Decimal>]
    def amount_and_quantity
      raise 'self subclass responsibility'
    end

    def enough_order_size?(quantity, price)
      (quantity * price) > MIN_AMOUNT
    end
  end
end

class OrderNotFound < StandardError; end
class ApiWrapperError < StandardError; end

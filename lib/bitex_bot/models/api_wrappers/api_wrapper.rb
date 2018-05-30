# This class represents the general behaviour for trading platform wrappers.
class ApiWrapper
  MIN_AMOUNT = 5

  Transaction = Struct.new(
    :id,       # Integer
    :price,    # Decimal
    :amount,   # Decimal
    :timestamp # Epoch Integer
  )

  Order = Struct.new(
    :id,        # String
    :type,      # Symbol
    :price,     # Decimal
    :amount,    # Decimal
    :timestamp, # Integer
    :raw_order  # Actual order object
  ) do
    def method_missing(method_name, *args, &block)
      raw_order.respond_to?(method_name) ? raw_order.send(method_name, *args, &block) : super
    end

    def respond_to_missing?(method_name, include_private = false)
      raw_order.respond_to?(method_name) || super
    end
  end

  OrderBook = Struct.new(
    :timestamp, # Integer
    :bids,      # [OrderSummary]
    :asks       # [OrderSummary]
  )

  OrderSummary = Struct.new(
    :price,   # Decimal
    :quantity # Decimal
  )

  BalanceSummary = Struct.new(
    :btc, # Balance
    :usd, # Balance
    :fee  # Decimal
  )

  Balance = Struct.new(
    :total,    # Decimal
    :reserved, # Decimal
    :available # Decimal
  )

  UserTransaction = Struct.new(
    :order_id, # Integer
    :usd,      # Decimal
    :btc,      # Decimal
    :btc_usd,  # Decimal
    :fee,      # Decimal
    :type,     # Integer
    :timestamp # Epoch Integer
  )

  # @return [Void]
  def self.setup(_settings)
    raise 'self subclass responsibility'
  end

  # @return [Array<Transaction>]
  def self.transactions
    raise 'self subclass responsibility'
  end

  # @return [OrderBook]
  def self.order_book(_retries = 20)
    raise 'self subclass responsibility'
  end

  # @return [BalanceSummary]
  def self.balance
    raise 'self subclass responsibility'
  end

  # @return [nil]
  def self.cancel
    raise 'self subclass responsibility'
  end

  # @return [Array<Order>]
  def self.orders
    raise 'self subclass responsibility'
  end

  # @return [UserTransaction]
  def self.user_transacitions
    raise 'self subclass responsibility'
  end

  # @param type
  # @param price
  # @param quantity
  def self.place_order(type, price, quantity)
    order = send_order(type, price, quantity)
    return order unless order.nil? || order.id.nil?

    BitexBot::Robot.log(:debug, "Captured error when placing order on #{self.class.name}")
    # Order may have gone through and be stuck somewhere in Wrapper's pipeline.
    # We just sleep for a bit and then look for the order.
    20.times do
      BitexBot::Robot.sleep_for(10)
      order = find_lost(type, price, quantity)
      return order if order.present?
    end
    raise OrderNotFound, "Closing: #{type} order not found for #{quantity} BTC @ $#{price}. #{order}"
  end

  # Hook Method - arguments could not be used in their entirety by the subclasses
  def self.send_order(_type, _price, _quantity)
    raise 'self subclass responsibility'
  end

  # @param order_method [String] buy|sell
  # @param price [Decimal]
  #
  # Hook Method - arguments could not be used in their entirety by the subclasses
  def self.find_lost(_type, _price, _quantity)
    raise 'self subclass responsibility'
  end

  # @param order_id
  # @param transactions
  #
  # @return [Array<Decimal, Decimal>]
  def self.amount_and_quantity(_order_id, _transactions)
    raise 'self subclass responsibility'
  end

  def self.enough_order_size?(quantity, price)
    (quantity * price) > MIN_AMOUNT
  end
end

class OrderNotFound < StandardError; end
class ApiWrapperError < StandardError; end

class ApiWrapper
  Transaction = Struct.new(
    :id, # Integer
    :price, # Decimal
    :amount, # Decimal
    :timestamp) # Integer

  Order = Struct.new(
    :id, # Integer
    :type, # Integer
    :price, # Decimal
    :amount, # Decimal
    :timestamp) # Integer

  OrderBook = Struct.new(
    :timestamp, # Integer
    :bids, # [OrderSummary]
    :asks) # [OrderSummary]

  OrderSummary = Struct.new(
    :price, # Decimal
    :quantity) # Decimal

  BalanceSummary = Struct.new(
    :btc, # Balance
    :usd, # Balance
    :fee) # Decimal

  Balance = Struct.new(
    :total, # Decimal
    :reserved, # Decimal
    :available) # Decimal

  UserTransaction = Struct.new(
    :usd, # Decimal
    :btc, # Decimal,
    :btc_usd, # Decimal
    :order_id, # Integer
    :fee, # Decimal,
    :type, # Integer
    :timestamp) # Integer

  # @return [Void]
  def self.setup(settings)
    raise 'self subclass responsibility'
  end

  # @return [Array<Transaction>]
  def self.transactions
    raise 'self subclass responsibility'
  end

  # @return [OrderBook]
  def self.order_book(retries = 20)
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

  # @param order_method [String] buy|sell
  # @param price [Decimal]
  def self.find_lost(order_method, price)
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
    raise 'self subclass responsibility'
  end

  # @param order_id
  # @param transactions
  # @return [Array<Decimal, Decimal>]
  def self.amount_and_quantity(order_id, transactions)
    raise 'self subclass responsibility'
  end
end

class ApiWrapperError < StandardError; end

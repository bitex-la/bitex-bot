class ApiWrapper
  Transaction = Struct.new(
    :id, # Integer
    :price, # Decimal
    :amount, # Decimal
    :timestamp) # Integer

  OrderBook = Struct.new(
    :timestamp, # Integer
    :bids, # [OrderSummary]
    :ask), # [OrderSummary]

  OrderSummary = Struct.new(
    :price, # Decimal
    :quantity) # Decimal

  AccountSummary = Struct.new(
    :btc, # Balance
    :usd, # Balance
    :fee) # Decimal

  Balance = Struct.new(
    :total, # Decimal
    :reserved, # Decimal
    :available) # Decimal

  BalanceSummary = Struct.new(
    :btc, # Balance
    :usd, # Balance
    :fee) # Decimal

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

  # {
  #   tid:i,
  #   date: (i+1).seconds.ago.to_i.to_s, TODO: date -> to timestamp, to_s -> to_i
  #   price: price.to_s,
  #   amount: amount.to_s
  # }
  #
  # @returns [Array<Transaction>]
  def self.transactions
    raise 'self subclass responsibility'
  end

  # {
  #   'timestamp' => DateTime.now.to_i.to_s,
  #   'bids' => [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
  #   'asks' => [['11', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
  # }
  #  TODO: bids and asks at now should be OrderSummary arrays, thne this should return OrderBook
  # @return [OrderBook]
  def self.order_book(retries = 20)
    raise 'self subclass responsibility'
  end

  # {
  #   'btc_balance'=> '10.0', 'btc_reserved'=> '0', 'btc_available'=> '10.0',
  #   'usd_balance'=> '100.0', 'usd_reserved'=>'0', 'usd_available'=> '100.0',
  #   'fee'=> '0.5000'
  # }
  #
  # TODO: btc_balance -> total, btc_reserved -> reserved, available -> btc_available
  # @return [BalanceSummary]
  def self.balance
    raise 'self subclass responsibility'
  end

  # double(
  #   id: remote_id,
  #   amount: args[:amount],
  #   price: args[:price],
  #   type: 1,
  #   datetime: DateTime.now.to_s)
  #
  # TODO: datetime -> timestamp: Integer
  # @return [Array<Order>] TODO: todos los orders comparten la misma estructura??
  def self.orders
    raise 'self subclass responsibility'
  end

  # @param order_method [String] buy|sell TODO: checkear que valores puede recibir en order_method
  # @param price [Decimal]
  def self.find_lost(order_method, price)
    raise 'self subclass responsibility'
  end

  # double(
  #   order_id: o.id,
  #   usd: (usd * ratio).to_s,
  #   btc: (btc * ratio).to_s,
  #   btc_usd: o.price.to_s,
  #   fee: '0.5',
  #   type: 2,
  #   datetime: DateTime.now.to_s)
  #
  # TODO: datetime -> timestamp: Integer, numeric -> decimal
  # @return [UserTransaction]
  def self.user_transacitions
    raise 'self subclass responsibility'
  end

  # TODO: definir los tipos de datos que se reciben como argumento
  # @param type
  # @param price
  # @param quantity
  def self.place_order(type, price, quantity)
    raise 'self subclass responsibility'
  end

  # TODO: definir los tipos de datos que se reciben como argumento
  # @param order_id
  # @param transactions
  # @return [Array<Decimal, Decimal>]
  def self.amount_and_quantity(order_id, transactions)
    raise 'self subclass responsibility'
  end
end

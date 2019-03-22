# This class represents the general behaviour for trading platform wrappers.
class ApiWrapper
  attr_accessor :currency_pair

  MIN_AMOUNT = 5

  Transaction = Struct.new(
    :id,        # Integer
    :price,     # Decimal
    :amount,    # Decimal
    :timestamp, # Epoch Integer
    :raw        # Actual transaction
  )

  Order = Struct.new(
    :id,        # String
    :type,      # Symbol <:bid|:ask>
    :price,     # Decimal
    :amount,    # Decimal
    :timestamp, # Integer
    :raw        # Actual order object
  ) do
    def method_missing(method_name, *args, &block)
      raw.respond_to?(method_name) ? raw.send(method_name, *args, &block) : super
    end

    def respond_to_missing?(method_name, include_private = false)
      raw.respond_to?(method_name) || super
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
    :type,        # String <buys|sells>
    :timestamp,   # Epoch Integer
    :raw
  )

  def name
    self.class.name.underscore.split('_').first.capitalize
  end

  # @return [Array<Transaction>]
  def transactions
    raise 'self subclass responsibility'
  end

  # @return [OrderBook]
  def market(_retries = 20)
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

  # @return [Array<UserTransaction>]
  def user_transactions
    raise 'self subclass responsibility'
  end

  # @param [Symbol] trade_type. <:buy|:sell>
  # @param [BigDecimal] price.
  # @param [BigDecimal] amount. Crypto amount.
  #
  # @return [Order|OrderNotFound]
  # rubocop:disable Metrics/AbcSize
  def place_order(trade_type, price, amount)
    threshold = 1.minute.ago.utc
    order = send_order(trade_type, price, amount)
    return order unless order.nil? || order.try(:id).nil?

    BitexBot::Robot.log(:error, "Captured error when placing order on #{name}")
    # Order may have gone through and be stuck somewhere in Wrapper's pipeline.
    # We just sleep for a bit and then look for the order.
    5.times do |i|
      BitexBot::Robot.log(
        :info,
        "#{name} cauldn't place #{trade_type} order #{i} times for #{base.upcase}"\
        " #{amount.truncate(8)} @ #{quote.upcase} #{price.truncate(8)}. Going to sleep 10 seconds."
      )

      BitexBot::Robot.sleep_for(10)
      order = find_lost(trade_type, price, amount, threshold)
      return order if order.present?
    end

    raise OrderNotFound, "Closing: #{trade_type} order not found for #{base.upcase} #{amount} @ #{quote.upcase} #{price}."
  end
  # rubocop:enable Metrics/AbcSize

  # Arguments could not be used in their entirety by the subclasses
  #
  # @param [Symbol] trade_type. <:buy|:sell>
  # @param [BigDecimal] price.
  # @param [BigDecimal] amount. Crypto amount.
  #
  # @return [Order|nil]
  def send_order(_trade_type, _price, _amount)
    raise 'self subclass responsibility'
  end

  # Arguments could not be used in their entirety by the subclasses
  #
  # @param [Symbol] trade_type. <:buy|:sell>
  # @param [BigDecimal] price.
  # @param [BigDecimal] amount. Crypto amount.
  #
  # @return [Order|OrderNotFound]
  def find_lost(_type, _price, _amount, _threshold)
    raise 'self subclass responsibility'
  end

  # Respont to minimun order size to place order.
  #
  # @param [BigDecimal] amount.
  # @param [BigDecimal] price.
  #
  # @return [Boolean]
  def enough_order_size?(amount, price, _trade_type = nil)
    amount* price > MIN_AMOUNT
  end

  def base_quote
    "#{base}_#{quote}"
  end

  def base
    currency_pair[:base]
  end

  def quote
    currency_pair[:quote]
  end
end

class OrderNotFound < StandardError; end
class ApiWrapperError < StandardError; end

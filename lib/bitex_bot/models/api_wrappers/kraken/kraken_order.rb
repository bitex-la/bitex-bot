require 'kraken_client'

# Wrapper for Kraken orders.
class KrakenOrder
  cattr_accessor :last_closed_order, :api_wrapper
  attr_accessor :id, :amount, :executed_amount, :price, :avg_price, :type, :datetime

  # rubocop:disable Metrics/AbcSize
  def self.create!(type, price, quantity)
    self.last_closed_order = closed.first.try(:id) || Time.now.to_i
    order = place_order(type, price.truncate(1), quantity.truncate(8))
    order_id = order['txid'].first
    find(order_id)
  rescue KrakenClient::ErrorResponse => e
    # Order could not be placed
    if e.message == 'EService:Unavailable'
      BitexBot::Robot.log(:debug, 'Captured EService:Unavailable error when placing order on Kraken. Retrying...')
      retry
    elsif e.message.start_with?('EGeneral:Invalid')
      BitexBot::Robot.log(:debug, "Captured #{e.message}: type: #{type}, price: #{price}, quantity: #{quantity}")
      raise OrderArgumentError, e.message
    elsif e.message != 'error'
      raise
    end
  end
  # rubocop:enable Metrics/AbcSize

  # <KrakenOrder:0x007faf255382d0 @id="OGZ3HI-5I322-OIOV52", @type=:sell, @datetime=1546971756, @amount=0.248752e-2,
  #  @executed_amount=0.248752e-2, @price=0.40025e4, @avg_price=0.40074e4>
  def self.place_order(type, price, quantity)
    api_wrapper.client.private.add_order(
      pair: api_wrapper.currency_pair[:altname],
      type: type,
      ordertype: 'limit',
      price: price,
      volume: quantity
    )
  end

  def self.find(id)
    new(*api_wrapper.client.private.query_orders(txid: id).first)
  rescue KrakenClient::ErrorResponse
    retry
  end

  # [BigDecimal, BigDecimal]
  def self.amount_and_quantity(order_id)
    order = find(order_id)
    amount = order.avg_price * order.executed_amount
    quantity = order.executed_amount

    [amount, quantity]
  end

  def self.open
    api_wrapper.client.private.open_orders['open'].map { |o| new(*o) }
  rescue KrakenClient::ErrorResponse
    retry
  end

  def self.closed(start: 1.hour.ago.to_i)
    api_wrapper.client.private.closed_orders(start: start)[:closed].map { |o| new(*o) }
  rescue KrakenClient::ErrorResponse
    retry
  end

  def self.find_lost(type, price, quantity)
    BitexBot::Robot.log(:debug, "Looking for #{type} order in open orders...")
    order = open_order_by(type, price.truncate(2), quantity.truncate(8))
    return log_and_return(order, :open) if order.present?

    BitexBot::Robot.log(:debug, "Looking for #{type} order in closed orders...")
    order = closed_order_by(type, price.truncate(2), quantity.truncate(8))
    return log_and_return(order, :closed) if order.present? && order.id != last_closed_order
  end

  def self.log_and_return(order, status)
    BitexBot::Robot.log(:debug, "Found open #{status} with ID #{order.id}")
    order
  end

  # description: [type, price, quantity]
  def self.open_order_by(type, price, quantity)
    open.detect { |order| order == [type, price, quantity] }
  end

  # description: [type, price, quantity]
  def self.closed_order_by(type, price, quantity)
    closed(start: last_closed_order).detect { |order| order == [type, price, quantity] }
  end

  # id: 'O5TDV2-WDYB2-6OGJRD'
  # order_data: {
  #     'refid': nil, 'userref': nil, 'status': 'open', 'opentm': 1440292821.4839, 'starttm': 0, 'expiretm': 0,
  #     'descr': {
  #       'pair': 'ETHEUR', 'type': 'buy', 'ordertype': 'limit', 'price': '1.19000', 'price2': '0', 'leverage': 'none',
  #       'order': 'buy 1204.00000000 ETHEUR @ limit 1.19000'
  #     },
  #     'vol': '1204.00000000', 'vol_exec': '0.00000000', 'cost': '0.00000', 'fee': '0.00000', 'price': '0.00000',
  #     'misc': '', 'oflags': 'fciq'
  #   }
  # }
  def initialize(id, order_data)
    self.id = id
    self.type = order_data[:descr][:type].to_sym
    self.datetime = order_data[:opentm].to_i
    self.amount = order_data[:vol].to_d
    self.executed_amount = order_data[:vol_exec].to_d
    self.price = order_data[:descr][:price].to_d
    self.avg_price = order_data[:price].to_d
  end

  def cancel!
    api_wrapper.client.private.cancel_order(txid: id)
  rescue KrakenClient::ErrorResponse => e
    e.message == 'EService:Unavailable' ? retry : raise
  end

  def ==(other)
    if other.is_a?(self.class)
      other.id == id
    elsif other.is_a?(Array)
      other == [type, price, amount]
    end
  end
end

class OrderArgumentError < StandardError; end

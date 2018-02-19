require 'kraken_client'

class KrakenOrder
  cattr_accessor :last_closed_order
  attr_accessor :id, :amount, :executed_amount, :price, :avg_price, :type, :datetime

  def initialize(id, order_data)
    self.id = id
    self.amount = order_data['vol'].to_d
    self.executed_amount = order_data['vol_exec'].to_d
    self.price = order_data['descr']['price'].to_d
    self.avg_price = order_data['price'].to_d
    self.type = order_data['descr']['type'].to_sym
    self.datetime = order_data['opentm'].to_i
  end

  def cancel!
    self.class.client.private.cancel_order(txid: id)
  rescue KrakenClient::ErrorResponse => e
    retry if e.message == 'EService:Unavailable'
    raise
  end

  def ==(order)
    if order.is_a?(self.class)
      id == order.id
    elsif order.is_a?(Array)
      [type, price, amount] == order
    end
  end

  def self.client
    KrakenApiWrapper.client
  end

  def self.find(id)
    new(*client.private.query_orders(txid: id).first)
  rescue KrakenClient::ErrorResponse => e
    retry
  end

  def self.amount_and_quantity(order_id, transactions)
    order = find(order_id)
    [order.avg_price * order.executed_amount, order.executed_amount]
  end

  def self.open
    client.private.open_orders['open'].collect { |o| new(*o) }
  rescue KrakenClient::ErrorResponse => e
    retry
  end

  def self.closed(start: 1.hour.ago.to_i)
    client.private.closed_orders(start: start)[:closed].collect { |o| new(*o) }
  rescue KrakenClient::ErrorResponse => e
    retry
  end

  def self.create!(type, price, quantity)
    self.last_closed_order = closed.first.try(:id) || Time.now.to_i
    price = price.truncate(1)
    quantity = quantity.truncate(8)
    order_info = client.private.add_order(pair: 'XBTUSD', type: type, ordertype: 'limit',
      price: price, volume: quantity)
    find(order_info['txid'].first)
  rescue KrakenClient::ErrorResponse => e
    # Order could not be placed
    if e.message == 'EService:Unavailable'
      BitexBot::Robot.logger.debug('Captured EService:Unavailable error when placing order on Kraken. Retrying...')
      retry
    elsif e.message.start_with?('EGeneral:Invalid')
      BitexBot::Robot.logger.debug("Captured #{e.message}: type: #{type}, price: #{price}, quantity: #{quantity}")
      raise OrderArgumentError.new(e.message)
      raise if e.message != 'error'
    end
  end

  def self.find_lost(type, price, quantity)
    BitexBot::Robot.logger.debug("Looking for #{type} order in open orders...")
    order_descr = [type, price, quantity]
    if order = open.detect { |o| o == order_descr }
      BitexBot::Robot.logger.debug("Found open order with ID #{order.id}")
      return order
    end

    BitexBot::Robot.logger.debug("Looking for #{type} order in closed orders...")
    order = closed(start: last_closed_order).detect { |o| o == order_descr }
    if order && order.id != last_closed_order
      BitexBot::Robot.logger.debug("Found closed order with ID #{order.id}")
      return order
    end
  end
end

class OrderArgumentError < StandardError; end
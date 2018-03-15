require 'kraken_client'

##
# Wrapper for Kraken orders.
#
class KrakenOrder
  cattr_accessor :last_closed_order
  attr_accessor :id, :amount, :executed_amount, :price, :avg_price, :type, :datetime

  class << self
    # rubocop:disable Metrics/AbcSize
    def create!(type, price, quantity)
      self.last_closed_order = closed.first.try(:id) || Time.now.to_i
      find(order_info_by(type, price.truncate(1), quantity.trucante(8))['txid'].first)
    rescue KrakenClient::ErrorResponse => e
      # Order could not be placed
      if e.message == 'EService:Unavailable'
        BitexBot::Robot.logger.debug('Captured EService:Unavailable error when placing order on Kraken. Retrying...')
        retry
      elsif e.message.start_with?('EGeneral:Invalid')
        BitexBot::Robot.logger.debug("Captured #{e.message}: type: #{type}, price: #{price}, quantity: #{quantity}")
        raise OrderArgumentError, e.message
      elsif e.message != 'error'
        raise
      end
    end
    # rubocop:enable Metrics/AbcSize

    def order_info_by(type, price, quantity)
      KrakenApiWrapper.client.private.add_order(pair: 'XBTUSD', type: type, ordertype: 'limit', price: price, volume: quantity)
    end

    def find(id)
      new(*KrakenApiWrapper.client.private.query_orders(txid: id).first)
    rescue KrakenClient::ErrorResponse
      retry
    end

    def amount_and_quantity(order_id)
      order = find(order_id)
      [order.avg_price * order.executed_amount, order.executed_amount]
    end

    def open
      KrakenApiWrapper.client.private.open_orders['open'].map { |o| new(*o) }
    rescue KrakenClient::ErrorResponse
      retry
    end

    def closed(start: 1.hour.ago.to_i)
      KrakenApiWrapper.client.private.closed_orders(start: start)[:closed].map { |o| new(*o) }
    rescue KrakenClient::ErrorResponse
      retry
    end

    def find_lost(type, price, quantity)
      BitexBot::Robot.logger.debug("Looking for #{type} order in open orders...")
      order = open_order_by(type, price, quantity)
      return log_and_return(order, :open) if order.present?

      BitexBot::Robot.logger.debug("Looking for #{type} order in closed orders...")
      order = closed_order_by(type, price, quantity)
      return log_and_return(order, :closed) if order && order.id != last_closed_order
    end

    def log_and_return(order, status)
      BitexBot::Robot.logger.debug("Found open #{status} with ID #{order.id}")
      order
    end

    # description: [type, price, quantity]
    def open_order_by(type, price, quantity)
      open.detect { |o| o == [type, price, quantity] }
    end

    # description: [type, price, quantity]
    def closed_order_by(type, price, quantity)
      closed(start: last_closed_order).detect { |o| o == [type, price, quantity] }
    end
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
  # rubocop:disable Metrics/AbcSize
  def initialize(id, order_data)
    self.id = id
    self.type = order_data[:descr][:type].to_sym
    self.datetime = order_data[:opentm].to_i
    self.amount = order_data[:vol].to_d
    self.executed_amount = order_data[:vol_exec].to_d
    self.price = order_data[:descr][:price].to_d
    self.avg_price = order_data[:price].to_d
  end
  # rubocop:enable Metrics/AbcSize

  def cancel!
    KrakenApiWrapper.client.private.cancel_order(txid: id)
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

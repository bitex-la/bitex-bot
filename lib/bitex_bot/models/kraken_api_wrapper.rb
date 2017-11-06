require 'kraken_client'

class KrakenApiWrapper
  def self.setup(settings)
    HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
    @settings = settings.kraken
  end

  def self.client
    @client ||= KrakenClient.load(@settings)
  end

  #{
  #  tid:i,
  #  date: (i+1).seconds.ago.to_i.to_s,
  #  price: price.to_s,
  #  amount: amount.to_s
  #}
  def self.transactions
    client.public.trades('XBTUSD')[:XXBTZUSD].reverse.collect do |t|
      Hashie::Mash.new({
        tid: t[2].to_s,
        price: t[0],
        amount: t[1],
        date: t[2]
      })
    end
  rescue NoMethodError => e
    retry
  end

  #  { 'timestamp' => DateTime.now.to_i.to_s,
  #    'bids' =>
  #      [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
  #    'asks' =>
  #      [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
  #  }
  def self.order_book(retries = 20)
    book = client.public.order_book('XBTUSD')[:XXBTZUSD]
    { 'bids' => book[:bids].collect { |b| [ b[0], b[1] ] },
      'asks' => book[:asks].collect { |a| [ a[0], a[1] ] } }
  rescue NoMethodError => e
    retry
  end

  # {"btc_balance"=> "10.0", "btc_reserved"=> "0", "btc_available"=> "10.0",
  # "usd_balance"=> "100.0", "usd_reserved"=>"0", "usd_available"=> "100.0",
  # "fee"=> "0.5000"}
  def self.balance
    balances = client.private.balance
    open_orders = KrakenOrder.open
    sell_orders = open_orders.select { |o| o.type == :sell }
    btc_reserved = sell_orders.collect { |o| o.amount - o.executed_amount }.sum
    buy_orders = open_orders - sell_orders
    usd_reserved = buy_orders.collect { |o| (o.amount - o.executed_amount) * o.price }.sum
    { 'btc_balance' => balances['XXBT'].to_d,
      'btc_reserved' => btc_reserved,
      'btc_available' => balances['XXBT'].to_d - btc_reserved,
      'usd_balance' => balances['ZUSD'].to_d,
      'usd_reserved' => usd_reserved,
      'usd_available' => balances['ZUSD'].to_d - usd_reserved,
      'fee' => client.private.trade_volume(pair: 'XBTUSD')[:fees][:XXBTZUSD][:fee].to_d
    }
  rescue KrakenClient::ErrorResponse, Net::ReadTimeout => e
    retry
  end

  # ask = double(amount: args[:amount], price: args[:price],
  #   type: 1, id: remote_id, datetime: DateTime.now.to_s)
  # ask.stub(:cancel!) do
  def self.orders
    KrakenOrder.open
  end

  # We don't need to fetch the list of transactions
  # for Kraken
  def self.user_transactions
    [ ]
  end

  def self.amount_and_quantity(order_id, transactions)
    KrakenOrder.amount_and_quantity(order_id, transactions)
  end

  def self.place_order(type, price, quantity)
    KrakenOrder.create(type, price, quantity)
  end
end

class KrakenOrder
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
  end

  def ==(order)
    if order.is_a?(self.class)
      id == order.id
    elsif order.is_a?(Array)
      [ type, price, amount ] == order
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
    [ order.avg_price * order.executed_amount, order.executed_amount ]
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

  def self.find_lost(type, price, quantity, last_closed_order)
    order_descr = [ type, price, quantity ]

    BitexBot::Robot.logger.debug("Looking for #{type} order in open orders...")
    if order = self.open.detect { |o| o == order_descr }
      BitexBot::Robot.logger.debug("Found open order with ID #{order.id}")
      return order
    end

    BitexBot::Robot.logger.debug("Looking for #{type} order in closed orders...")
    order = closed(start: last_closed_order).detect { |o| o == order_descr }
    if order && order.id != last_closed_order
      BitexBot::Robot.logger.debug("Found closed order with ID #{id}")
      return order
    end
  end

  def self.create(type, price, quantity)
    last_closed_order = closed.first.try(:id) || Time.now.to_i
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
      return
    end
    raise unless e.message == 'error'
    BitexBot::Robot.logger.debug('Captured error when placing order on Kraken')
    # Order may have gone through and be stuck somewhere in Kraken's
    # pipeline. We just sleep for a bit and then look for the order.
    8.times do
      sleep 15
      order = find_lost(type, price, quantity, last_closed_order)
      return order if order
    end
    raise
  end
end

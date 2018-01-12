class BitstampApiWrapper < ApiWrapper
  def self.setup(settings)
    Bitstamp.setup do |config|
      config.key = settings.bitstamp.api_key
      config.secret = settings.bitstamp.secret
      config.client_id = settings.bitstamp.client_id.to_s
    end
  end

  def self.transactions; Bitstamp.transactions; end

  def self.order_book(retries = 20)
    book = Bitstamp.order_book
    age = Time.now.to_i - book['timestamp'].to_i

    return book unless age > 300
    BitexBot::Robot.logger.info("Refusing to continue as orderbook is #{age} seconds old")
    self.order_book(retries)
  rescue StandardError => e
    raise if retries == 0
    BitexBot::Robot.logger.info("Bitstamp order_book failed, retrying #{retries} more times")
    BitexBot::Robot.sleep_for 1
    self.order_book(retries - 1)
  end

  def self.balance; Bitstamp.balance; end

  def self.orders
    Bitstamp.orders.all.map { |o| order_parser(o) }
  end

  def self.find_lost(order_method, price)
    orders.find do |o|
      o.order_method == order_method &&
      o.price == price &&
      o.datetime.to_datetime >= 5.minutes.ago.to_datetime
    end
  end

  def self.user_transactions; Bitstamp.user_transactions.all; end

  def self.place_order(type, price, quantity)
    Bitstamp.orders.send(type, amount: quantity.round(4), price: price.round(2))
  end

  def self.amount_and_quantity(order_id, transactions)
    closes = transactions.select{ |t| t.order_id.to_s == order_id }
    amount = closes.collect{ |c| c.usd.to_d }.sum.abs
    quantity = closes.collect{ |c| c.btc.to_d }.sum.abs
    [amount, quantity]
  end

  private

  def self.order_is_done?(order); order.nil?; end

  # order = {
  #   'id': 7, 'price': '1.12', 'amount': '1', 'type': 0, 'datetime': '2013-09-26 23:26:56.84'
  # }
  def self.order_parser(order)
    Order.new(order[:id], order[:price].to_d, order[:amount].to_d, Time.new(order[:datetime].to_i))
  end
end

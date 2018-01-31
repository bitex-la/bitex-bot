class BitstampApiWrapper < ApiWrapper
  def self.setup(settings)
    Bitstamp.setup do |config|
      config.key = settings.bitstamp.api_key
      config.secret = settings.bitstamp.secret
      config.client_id = settings.bitstamp.client_id.to_s
    end
  end

  def self.transactions
    Bitstamp.transactions.map { |t| transaction_parser(t) }
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp transactions failed: #{e.message}")
  end

  def self.order_book(retries = 20)
    book = Bitstamp.order_book
    age = Time.now.to_i - book['timestamp'].to_i

    return order_book_parser(book) if age <= 300
    BitexBot::Robot.logger.info("Refusing to continue as orderbook is #{age} seconds old")
    self.order_book(retries)
  rescue StandardError => e
    raise if retries == 0
    BitexBot::Robot.logger.info("Bitstamp order_book failed, retrying #{retries} more times")
    BitexBot::Robot.sleep_for 1
    self.order_book(retries - 1)
  end

  def self.balance
    balance_summary_parser(Bitstamp.balance)
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp balance failed: #{e.message}")
  end

  def self.cancel(order)
    Bitstamp::Order.new(id: order.id).cancel!
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp cancel! failed: #{e.message}")
  end

  def self.orders
    Bitstamp.orders.all.map { |o| order_parser(o) }
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp orders failed: #{e.message}")
  end

  def self.user_transactions
    Bitstamp.user_transactions.all.map { |ut| user_transaction_parser(ut) }
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp user_transactions failed: #{e.message}")
  end

  def self.place_order(type, price, quantity)
    Bitstamp.orders.send(type, amount: quantity.round(4), price: price.round(2))
  end

  def self.find_lost(order_method, price)
    orders.find do |o|
      o.order_method == order_method &&
      o.price == price &&
      o.datetime.to_datetime >= 5.minutes.ago.to_datetime
    end
  end

  def self.amount_and_quantity(order_id, transactions)
    closes = transactions.select { |t| t.order_id.to_s == order_id }
    amount = closes.collect { |c| c.usd.to_d }.sum.abs
    quantity = closes.collect { |c| c.btc.to_d }.sum.abs
    [amount, quantity]
  end

  private

  def self.order_is_done?(o); o.nil?; end

  def self.order_parser(o)
    Order.new(o.id, o.type, o.price.to_d, o.amount.to_d, DateTime.parse(o.datetime).to_time.to_i)
  end

  def self.transaction_parser(t)
    Transaction.new(t.tid, t.price.to_d, t.amount.to_d, t.date.to_i)
  end

  def self.order_book_parser(ob)
    OrderBook.new(
      ob['timestamp'].to_i,
      ob['bids'].map { |b| OrderSummary.new(b[0].to_d, b[1].to_d) },
      ob['asks'].map { |a| OrderSummary.new(a[0].to_d, a[1].to_d) }
    )
  end

  def self.balance_summary_parser(b)
    BalanceSummary.new(
      Balance.new(b['btc_balance'].to_d, b['btc_reserved'].to_d, b['btc_available'].to_d),
      Balance.new(b['usd_balance'].to_d, b['usd_reserved'].to_d, b['usd_available'].to_d),
      b['fee'].to_d
    )
  end

  def self.user_transaction_parser(ut)
    UserTransaction.new(
      ut.usd.to_d,
      ut.btc.to_d,
      ut.btc_usd.to_d,
      ut.order_id,
      ut.fee.to_d,
      ut.type,
      Time.new(ut.datetime.to_i).to_i
    )
  end
end

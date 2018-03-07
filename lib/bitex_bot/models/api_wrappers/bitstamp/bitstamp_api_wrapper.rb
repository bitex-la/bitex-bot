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

  def self.orders
    Bitstamp.orders.all.map { |o| order_parser(o) }
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp orders failed: #{e.message}")
  end

  def self.order_book(retries = 20)
    book = Bitstamp.order_book.deep_symbolize_keys
    age = Time.now.to_i - book[:timestamp].to_i

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
    balance_summary_parser(Bitstamp.balance.symbolize_keys)
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp balance failed: #{e.message}")
  end

  def self.cancel(order)
    Bitstamp::Order.new(id: order.id).cancel!
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp cancel! failed: #{e.message}")
  end


  def self.user_transactions
    Bitstamp.user_transactions.all.map { |ut| user_transaction_parser(ut) }
  rescue StandardError => e
    raise ApiWrapperError.new("Bitstamp user_transactions failed: #{e.message}")
  end

  def self.send_order(type, price, quantity)
    Bitstamp.orders.send(type, amount: quantity.round(4), price: price.round(2))
  end

  def self.find_lost(type, price, quantity)
    orders.find do |o|
      o.order_method == type &&
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

  def self.order_is_done?(o)
    o.nil?
  end

  # <Bitstamp::Transactions: @tid=1469074, @price='126.95', @amount='1.10000000', @date='1380648951'>
  def self.transaction_parser(t)
    Transaction.new(t.tid, t.price.to_d, t.amount.to_d, t.date.to_i)
  end

  # <Bitstamp::Order: @id=7630204, @type=0, @price='1.01', @amount='1.00000000', @datetime='2013-09-26 23:15:04'>
  def self.order_parser(o)
    timestamp = DateTime.parse(o.datetime).to_time.to_i
    type = o.type == 0 ? :buy : :sell
    Order.new(o.id.to_s, type, o.price.to_d, o.amount.to_d, timestamp)
  end

  # {
  #   timestamp: '1380237884',
  #   bids: [['124.55', '1.58057006'], ['124.40', '14.91779125']],
  #   asks: [['124.56', '0.81888247'], ['124.57', '0.81078911']]
  # }
  def self.order_book_parser(ob)
    OrderBook.new(
      ob[:timestamp].to_i,
      ob[:bids].map { |bid| OrderSummary.new(bid[0].to_d, bid[1].to_d) },
      ob[:asks].map { |ask| OrderSummary.new(ask[0].to_d, ask[1].to_d) }
    )
  end

  # {
  #   btc_reserved: '0', btc_available: '0', btc_balance: '0',
  #   usd_reserved: '1.02, usd_available: '6952.05', usd_balance: '6953.07',
  #   fee: '0.4000'
  # }
  def self.balance_summary_parser(b)
    BalanceSummary.new(
      Balance.new(b[:btc_balance].to_d, b[:btc_reserved].to_d, b[:btc_available].to_d),
      Balance.new(b[:usd_balance].to_d, b[:usd_reserved].to_d, b[:usd_available].to_d),
      b[:fee].to_d
    )
  end

  # <Bitstamp::UserTransaction:
  #   @usd='-373.51', @btc='3.00781124', @btc_usd='124.18', @order_id=7623942, @fee='1.50', @type=2, @id=1444404,
  #   @datetime='2013-09-26 13:28:55'
  # >
  def self.user_transaction_parser(ut)
    timestamp = Time.new(ut.datetime).to_i
    UserTransaction.new(ut.order_id, ut.usd.to_d, ut.btc.to_d, ut.btc_usd.to_d, ut.fee.to_d, ut.type, timestamp)
  end
end

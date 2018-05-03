##
# Wrapper implementation for Bitstamp API.
# https://www.bitstamp.net/api/
#
class BitstampApiWrapper < ApiWrapper
  def self.setup(settings)
    Bitstamp.setup do |config|
      config.key = settings.bitstamp.api_key
      config.secret = settings.bitstamp.secret
      config.client_id = settings.bitstamp.client_id.to_s
    end
  end

  def self.amount_and_quantity(order_id, transactions)
    closes = transactions.select { |t| t.order_id.to_s == order_id }
    amount = closes.map { |c| c.usd.to_d }.sum.abs
    quantity = closes.map { |c| c.btc.to_d }.sum.abs
    [amount, quantity]
  end

  def self.balance
    balance_summary_parser(Bitstamp.balance.symbolize_keys)
  rescue StandardError => e
    raise ApiWrapperError, "Bitstamp balance failed: #{e.message}"
  end

  def self.cancel(order)
    Bitstamp::Order.new(id: order.id).cancel!
  rescue StandardError => e
    raise ApiWrapperError, "Bitstamp cancel! failed: #{e.message}"
  end

  def self.find_lost(type, price)
    orders.find do |o|
      o.order_method == type &&
        o.price == price &&
        o.datetime.to_datetime >= 5.minutes.ago.to_datetime
    end
  end

  # rubocop:disable Metrics/AbcSize
  def self.order_book(retries = 20)
    book = Bitstamp.order_book.deep_symbolize_keys
    age = Time.now.to_i - book[:timestamp].to_i

    return order_book_parser(book) if age <= 300
    BitexBot::Robot.log(:info, "Refusing to continue as orderbook is #{age} seconds old")
    order_book(retries)
  rescue StandardError
    raise if retries.zero?
    BitexBot::Robot.log(:info, "Bitstamp orderbook failed, retrying #{retries} more times")
    BitexBot::Robot.sleep_for 1
    order_book(retries - 1)
  end
  # rubocop:enable Metrics/AbcSize

  def self.orders
    Bitstamp.orders.all.map { |o| order_parser(o) }
  rescue StandardError => e
    raise ApiWrapperError, "Bitstamp orders failed: #{e.message}"
  end

  def self.send_order(type, price, quantity)
    Bitstamp.orders.send(type, amount: quantity.round(4), price: price.round(2))
  end

  def self.transactions
    Bitstamp.transactions.map { |t| transaction_parser(t) }
  rescue StandardError => e
    raise ApiWrapperError, "Bitstamp transactions failed: #{e.message}"
  end

  def self.user_transactions
    Bitstamp.user_transactions.all.map { |ut| user_transaction_parser(ut) }
  rescue StandardError => e
    raise ApiWrapperError, "Bitstamp user_transactions failed: #{e.message}"
  end

  private_class_method

  # {
  #   btc_reserved: '0', btc_available: '0', btc_balance: '0',
  #   usd_reserved: '1.02, usd_available: '6952.05', usd_balance: '6953.07',
  #   fee: '0.4000'
  # }
  def self.balance_summary_parser(balances)
    BalanceSummary.new(balance_parser(balances, :btc), balance_parser(balances, :usd), balances[:fee].to_d)
  end

  def self.balance_parser(balances, currency)
    Balance.new(
      balances["#{currency}_balance".to_sym].to_d,
      balances["#{currency}_reserved".to_sym].to_d,
      balances["#{currency}_available".to_sym].to_d
    )
  end

  # {
  #   timestamp: '1380237884',
  #   bids: [['124.55', '1.58057006'], ['124.40', '14.91779125']],
  #   asks: [['124.56', '0.81888247'], ['124.57', '0.81078911']]
  # }
  def self.order_book_parser(book)
    OrderBook.new(book[:timestamp].to_i, order_summary_parser(book[:bids]), order_summary_parser(book[:asks]))
  end

  def self.order_is_done?(order)
    order.nil?
  end

  # <Bitstamp::Order @id=76, @type=0, @price='1.1', @amount='1.0', @datetime='2013-09-26 23:15:04'>
  def self.order_parser(order)
    type = order.type.zero? ? :buy : :sell
    Order.new(order.id.to_s, type, order.price.to_d, order.amount.to_d, order.datetime.to_time.to_i)
  end

  def self.order_summary_parser(orders)
    orders.map { |order| OrderSummary.new(order[0].to_d, order[1].to_d) }
  end

  # <Bitstamp::Transactions: @tid=1469074, @price='126.95', @amount='1.10000000', @date='1380648951'>
  def self.transaction_parser(transaction)
    Transaction.new(transaction.tid, transaction.price.to_d, transaction.amount.to_d, transaction.date.to_i)
  end

  # <Bitstamp::UserTransaction:
  #   @usd='-373.51', @btc='3.00781124', @btc_usd='124.18', @order_id=7623942, @fee='1.50', @type=2, @id=1444404,
  #   @datetime='2013-09-26 13:28:55'
  # >
  def self.user_transaction_parser(user_transaction)
    timestamp = Time.new(user_transaction.datetime).to_i
    UserTransaction.new(
      user_transaction.order_id,
      user_transaction.usd.to_d,
      user_transaction.btc.to_d,
      user_transaction.btc_usd.to_d,
      user_transaction.fee.to_d,
      user_transaction.type,
      timestamp
    )
  end
end

##
# Wrapper implementation for Bitfinex API.
# https://docs.bitfinex.com/docs
#
class BitfinexApiWrapper < ApiWrapper
  cattr_accessor(:max_retries) { 1000 }

  def self.client
    @client ||= Bitfinex::Client.new
  end

  def self.setup(settings)
    Bitfinex::Client.configure do |conf|
      conf.api_key = settings.bitfinex.api_key
      conf.secret = settings.bitfinex.api_secret
    end
  end

  def self.amount_and_quantity(order_id, _transactions)
    with_retry "find order #{order_id}" do
      order = Bitfinex::Client.new.order_status(order_id)
      [order['avg_execution_price'].to_d * order['executed_amount'].to_d, order['executed_amount'].to_d]
    end
  end

  def self.balance
    with_retry :balance do
      balances = client.balances(type: 'exchange').map(&:symbolize_keys)
      balance_summary_parser(balances)
    end
  end

  def self.orders
    with_retry :orders do
      client.orders.map { |o| order_parser(o.symbolize_keys) }
    end
  end

  def self.order_book
    with_retry :order_book do
      order_book_parser(client.orderbook.deep_symbolize_keys)
    end
  end

  def self.place_order(type, price, quantity)
    with_retry "place order #{type} #{price} #{quantity}" do
      order_data = client.new_order('btcusd', quantity.round(4), 'exchange limit', type.to_s, price.round(2))
      BitfinexOrder.new(order_data)
    end
  end

  def self.transactions
    with_retry :transactions do
      client.trades.map { |t| transaction_parser(t.symbolize_keys) }
    end
  end

  # We don't need to fetch the list of transactions for bitfinex
  def self.user_transactions
    []
  end

  private_class_method

  def self.with_retry(action, retries = 0)
    yield
  rescue StandardError, Bitfinex::ClientError
    BitexBot::Robot.logger.info("Bitfinex #{action} failed. Retrying in 5 seconds.")
    BitexBot::Robot.sleep_for 5
    if retries < max_retries
      with_retry(action, retries + 1, &block)
    else
      BitexBot::Robot.logger.info("Bitfinex #{action} failed. Gave up.")
      raise
    end
  end

  # [
  #   { type: 'exchange', currency: 'btc', amount: '0.0', available: '0.0' },
  #   { type: 'exchange', currency: 'usd', amount: '0.0', available: '0.0' },
  #   ...
  # ]
  def self.balance_summary_parser(balances)
    BalanceSummary.new(
      balance_parser(balances, 'btc'),
      balance_parser(balances, 'usd'),
      client.account_info.first[:taker_fees].to_d
    )
  end

  def self.balance_parser(balances, currency)
    currency_balance = balances.find { |balance| balance[:currency] == currency } || {}
    Balance.new(
      currency_balance[:amount].to_d,
      currency_balance[:amount].to_d - currency_balance[:available].to_d,
      currency_balance[:available].to_d
    )
  end

  # {
  #   id: 448411365, symbol: 'btcusd', exchange: 'bitfinex', price: '0.02', avg_execution_price: '0.0',  side: 'buy',
  #   type: 'exchange limit', timestamp: '1444276597.0', is_live: true, is_cancelled: false, is_hidden: false,
  #   was_forced: false, original_amount: '0.02', remaining_amount: '0.02', executed_amount: '0.0'
  # }
  def self.order_parser(order)
    Order
      .new(order[:id].to_s, order[:side].to_sym, order[:price].to_d, order[:original_amount].to_d, order[:timestamp].to_i, order)
  end

  # {
  #   bids: [{ price: '574.61', amount: '0.14397', timestamp: '1472506127.0' }],
  #   asks: [{ price: '574.62', amount: '19.1334', timestamp: '1472506126.0 '}]
  # }
  def self.order_book_parser(book)
    OrderBook.new(Time.now.to_i, order_summary(book[:bids]), order_summary(book[:asks]))
  end

  def self.order_summary(orders)
    orders.map { |stock| OrderSummary.new(stock[:price].to_d, stock[:amount].to_d) }
  end

  # { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 }
  def self.transaction_parser(transaction)
    Transaction.new(transaction[:tid], transaction[:price].to_d, transaction[:amount].to_d, transaction[:timestamp])
  end
end

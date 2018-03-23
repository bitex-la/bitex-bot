class BitfinexApiWrapper < ApiWrapper
  cattr_accessor :max_retries do 1000 end

  def self.setup(settings)
    Bitfinex::Client.configure do |conf|
      conf.api_key = settings.bitfinex.api_key
      conf.secret = settings.bitfinex.api_secret
    end
  end

  def self.transactions
    with_retry 'transactions' do
      client.trades.map { |t| transaction_parser(t.symbolize_keys) }
    end
  end

  def self.orders
    with_retry 'orders' do
      client.orders.map { |o| order_parser(BitfinexOrder.new(o)) }
    end
  end

  def self.order_book
    with_retry 'order_book' do
      book = client.orderbook.deep_symbolize_keys
      order_book_parser(book)
    end
  end

  def self.balance
    with_retry 'balance' do
      balances = client.balances(type: 'exchange').map(&:symbolize_keys)
      balance_summary_parser(balances)
    end
  end

  # We don't need to fetch the list of transactions for bitfinex
  def self.user_transactions
    []
  end

  def self.place_order(type, price, quantity)
    with_retry "place order #{type} #{price} #{quantity}" do
      order_data =
        Bitfinex::Client.new
        .new_order('btcusd', quantity.round(4), 'exchange limit', type.to_s, price.round(2))
      BitfinexOrder.new(order_data)
    end
  end

  def self.amount_and_quantity(order_id, transactions)
    with_retry "find order #{order_id}" do
      order = Bitfinex::Client.new.order_status(order_id)
      [order['avg_execution_price'].to_d * order['executed_amount'].to_d, order['executed_amount'].to_d]
    end
  end

  def self.client
    @client ||= Bitfinex::Client.new
  end

  private

  def self.with_retry(action, retries = 0, &block)
    block.call
  rescue StandardError, Bitfinex::ClientError => e
    BitexBot::Robot.logger.info("Bitfinex #{action} failed. Retrying in 5 seconds.")
    BitexBot::Robot.sleep_for 5
    if retries < max_retries
      with_retry(action, retries + 1, &block)
    else
      BitexBot::Robot.logger.info("Bitfinex #{action} failed. Gave up.")
      raise
    end
  end

  # { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 }
  def self.transaction_parser(t)
    Transaction.new(t[:tid], t[:price].to_d, t[:amount].to_d, t[:timestamp])
  end

  # {
  #   id: 448411365, symbol: 'btcusd', exchange: 'bitfinex', price: '0.02', avg_execution_price: '0.0',  side: 'buy',
  #   type: 'exchange limit', timestamp: '1444276597.0', is_live: true, is_cancelled: false, is_hidden: false,
  #   was_forced: false, original_amount: '0.02', remaining_amount: '0.02', executed_amount: '0.0'
  # }
  def self.order_parser(o)
    Order.new(o.id.to_s, o.type, o.price, o.amount, o.datetime, o)
  end

  # [
  #   { type: 'deposit', currency: 'btc', amount: '0.0', available: '0.0' },
  #   { type: 'deposit', currency: 'usd', amount: '1.0', available: '1.0' },
  #   { type: 'exchange', currency: 'btc', amount: '1', available: '1' }
  # ]
  def self.balance_summary_parser(b)
    BalanceSummary.new.tap do |summary|
      btc = b.find { |balance| balance[:currency] == 'btc' } || {}
      summary[:btc] = Balance.new(btc[:amount].to_d, btc[:amount].to_d - btc[:available].to_d, btc[:available].to_d)

      usd = b.find { |balance| balance[:currency] == 'usd' } || {}
      summary[:usd] = Balance.new(usd[:amount].to_d, usd[:amount].to_d - usd[:available].to_d, usd[:available].to_d)

      summary[:fee] = client.account_info.first[:taker_fees].to_d
    end
  end

  # {
  #   bids: [{ price: '574.61', amount: '0.14397', timestamp: '1472506127.0' }],
  #   asks: [{ price: '574.62', amount: '19.1334', timestamp: '1472506126.0 '}]
  # }
  def self.order_book_parser(b)
    OrderBook.new(
      Time.now.to_i,
      b[:bids].map { |bid| OrderSummary.new(bid[:price].to_d, bid[:amount].to_d) },
      b[:asks].map { |ask| OrderSummary.new(ask[:price].to_d, ask[:amount].to_d) }
    )
  end
end

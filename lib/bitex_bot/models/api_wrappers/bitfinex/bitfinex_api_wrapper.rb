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
      Bitfinex::Client.new.trades.collect do |t|
        Hashie::Mash.new(tid: t['tid'].to_i, price: t['price'], amount: t['amount'], date: t['timestamp'])
      end
    end
  end

  def self.order_book
    with_retry 'order_book' do
      book = Bitfinex::Client.new.orderbook
      {
        'bids' => book['bids'].collect { |b| [b['price'], b['amount']] },
        'asks' => book['asks'].collect { |a| [a['price'], a['amount']] }
      }
    end
  end

  def self.balance
    with_retry 'balance' do
      balances = Bitfinex::Client.new.balances(type: 'exchange')
      BitexBot::Robot.sleep_for 1 # Sleep to avoid sending two consecutive requests to bitfinex.
      fee = Bitfinex::Client.new.account_info.first['taker_fees']
      btc = balances.find { |b| b['currency'] == 'btc' } || {}
      usd = balances.find { |b| b['currency'] == 'usd' } || {}
      {
        'btc_balance' => btc['amount'].to_d,
        'btc_reserved' => btc['amount'].to_d - btc['available'].to_d,
        'btc_available' => btc['available'].to_d,
        'usd_balance' => usd['amount'].to_d,
        'usd_reserved' => usd['amount'].to_d - usd['available'].to_d,
        'usd_available' => usd['available'].to_d,
        'fee' => fee.to_d
      }
    end
  end

  def self.orders
    with_retry 'orders' do
      Bitfinex::Client.new.orders.collect { |o| BitfinexOrder.new(o) }
    end
  end

  # We don't need to fetch the list of transactions for bitfinex
  def self.user_transactions
    []
  end

  def self.place_order(type, price, quantity)
    with_retry "place order #{type} #{price} #{quantity}" do
      order_data = Bitfinex::Client.new
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
end

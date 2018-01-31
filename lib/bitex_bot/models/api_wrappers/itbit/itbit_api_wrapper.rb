class ItbitApiWrapper < ApiWrapper
  def self.setup(settings)
    Itbit.tap do |conf|
      conf.client_key = settings.itbit.client_key
      conf.secret = settings.itbit.secret
      conf.user_id = settings.itbit.user_id
      conf.default_wallet_id = settings.itbit.default_wallet_id
      conf.sandbox = settings.sandbox
    end
  end

  def self.transactions
    Itbit::XBTUSDMarketData.trades.collect { |t| Hashie::Mash.new(t) }
  end

  def self.order_book
    Itbit::XBTUSDMarketData.orders.stringify_keys
  end

  def self.balance
    balances = Itbit::Wallet.all.find { |w| w[:id] == Itbit.default_wallet_id }[:balances]
    usd = balances.find { |b| b[:currency] == :usd }
    btc = balances.find { |b| b[:currency] == :xbt }
    {
      'btc_balance' => btc[:total_balance],
      'btc_reserved' => btc[:total_balance] - btc[:available_balance],
      'btc_available' => btc[:available_balance],
      'usd_balance' => usd[:total_balance],
      'usd_reserved' => usd[:total_balance] - usd[:available_balance],
      'usd_available' => usd[:available_balance],
      'fee' => 0.5
    }
  end

  def self.orders
    Itbit::Order.all(status: :open)
  end

  def self.find_lost(order_method, price)
    orders.find do |o|
      o.order_method == order_method &&
        o.price == price &&
        Time.at(o.created_time).to_datetime >= 5.minutes.ago.to_datetime
    end
  end

  # We don't need to fetch the list of transaction for itbit since we wont actually use them later.
  def self.user_transactions
    []
  end

  def self.place_order(type, price, quantity)
    Itbit::Order.create!(type, :xbtusd, quantity.round(4), price.round(2), wait: true)
  rescue RestClient::RequestTimeout => e
    # On timeout errors, we still look for the latest active closing order that may be available.
    # We have a magic threshold of 5 minutes and also use the price to recognize an order as the
    # current one.
    # TODO: Maybe we can identify the order using metadata instead of price.
    BitexBot::Robot.logger.error('Captured Timeout on itbit')
    latest = Itbit::Order.all.select do |o|
      o.price == price && (o.created_time - Time.now.to_i).abs < 500
    end.first

    return latest if latest.present?
    BitexBot::Robot.logger.error('Could not find my order')
    raise e
  end

  def self.amount_and_quantity(order_id, transactions)
    order = Itbit::Order.find(order_id)
    [order.volume_weighted_average_price * order.amount_filled, order.amount_filled]
  end
end

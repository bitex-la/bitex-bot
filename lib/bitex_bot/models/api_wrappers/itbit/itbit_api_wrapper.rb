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
    Itbit::XBTUSDMarketData.trades.map { |t| transaction_parser(t.symbolize_keys) }
  end

  def self.orders
    Itbit::Order.all(status: :open).map { |o| order_parser(o) }
  end

  def self.order_book
    order_book_parser(Itbit::XBTUSDMarketData.orders)
  end

  def self.balance
    wallet = Itbit::Wallet.all.find { |w| w[:id] == Itbit.default_wallet_id }
    balance_summary_parser(wallet[:balances])
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
    # We have a magic threshold of 5 minutes and also use the price to recognize an order as the current one.
    # TODO: Maybe we can identify the order using metadata instead of price.
    BitexBot::Robot.logger.error('Captured Timeout on itbit')
    latest =
      Itbit::Order.all.select do |o|
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

  private

  # { tid: 601855, price: 0.41814e3, amount: 0.19e-1, date: 1460161126 }
  def self.transaction_parser(t)
    Transaction.new(t[:tid], t[:price], t[:amount], t[:date])
  end

  # <Itbit::Order:
  #   @id='8fd820d3-baff-4d6f-9439-ff03d816c7ce', @wallet_id='b440efce-a83c-4873-8833-802a1022b476', @side=:buy,
  #   @instrument=:xbtusd, @type=:limit, @amount=0.1005e1, @display_amount=0.1005e1, @price=0.1e3,
  #   @volume_weighted_average_price=0.0, @amount_filled=0.0, @created_time=1415290187, @status=:open,
  #   @metadata={foo: 'bar'}, @client_order_identifier='o'
  # >
  def self.order_parser(o)
    Order.new(o.id, o.side, o.price, o.amount, o.created_time, o)
  end

  # {
  #   bids: [[0.63921e3, 0.195e1], [0.637e3, 0.47e0], [0.63e3, 0.158e1]],
  #   asks: [[0.6424e3, 0.4e0], [0.6433e3, 0.95e0], [0.6443e3, 0.25e0]]
  # }
  def self.order_book_parser(ob)
    OrderBook.new(
      Time.now.to_i,
      ob[:bids].map { |bid| OrderSummary.new(bid[0], bid[1]) },
      ob[:asks].map { |ask| OrderSummary.new(ask[0], ask[1]) }
    )
  end

  # [
  #   { total_balance: 0.2e2, currency: :usd, available_balance: 0.1e2 },
  #   { total_balance: 0.0, currency: :xbt, available_balance: 0.0 },
  #   { total_balance: 0.0, currency: :eur, available_balance: 0.0 },
  #   { total_balance: 0.0, currency: :sgd, available_balance: 0.0 }
  # ]
  def self.balance_summary_parser(b)
    BalanceSummary.new.tap do |summary|
      btc = b.find { |balance| balance[:currency] == :xbt }
      summary[:btc] =
        Balance.new(btc[:total_balance], btc[:total_balance] - btc[:available_balance], btc[:available_balance])

      usd = b.find { |balance| balance[:currency] == :usd }
      summary[:usd] =
        Balance.new(usd[:total_balance], usd[:total_balance] - usd[:available_balance], usd[:available_balance])

      summary[:fee] = 0.5.to_d
    end
  end
end

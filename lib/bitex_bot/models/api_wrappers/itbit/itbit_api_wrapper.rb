# Wrapper implementation for Itbit API.
# https://api.itbit.com/docs
class ItbitApiWrapper < ApiWrapper
  attr_accessor :client_key, :secret, :user_id, :default_wallet_id, :sandbox

  def initialize(settings)
    self.client_key = settings.client_key
    self.secret = settings.secret
    self.user_id = settings.user_id
    self.default_wallet_id = settings.default_wallet_id
    self.sandbox = settings.sandbox
    currency_pair(settings.order_book)
    setup
  end

  def setup
    Itbit.tap do |conf|
      conf.client_key = client_key
      conf.secret = secret
      conf.user_id = user_id
      conf.default_wallet_id = default_wallet_id
      conf.sandbox = sandbox
    end
  end

  def amount_and_quantity(order_id)
    order = Itbit::Order.find(order_id)
    amount = order.volume_weighted_average_price * order.amount_filled
    quantity = order.amount_filled

    [amount, quantity]
  end

  def balance
    balance_summary_parser(wallet[:balances])
  end

  def find_lost(type, price, _quantity)
    orders.find { |o| o.type == type && o.price == price && o.timestamp >= 5.minutes.ago.to_i }
  end

  def order_book
    order_book_parser(market.orders)
  end

  def orders
    Itbit::Order.all(instrument: currency_pair[:name], status: :open).map { |o| order_parser(o) }
  end

  def send_order(type, price, quantity)
    order = Itbit::Order.create!(
      type,
      currency_pair[:name],
      quantity.round(4),
      price.round(2),
      wait: true,
      currency: currency_pair[:base]
    )
    order_parser(order) if order.present?
  rescue RestClient::RequestTimeout => e
    # On timeout errors, we still look for the latest active closing order that may be available.
    # We have a magic threshold of 5 minutes and also use the price to recognize an order as the current one.
    # TODO: Maybe we can identify the order using metadata instead of price.
    BitexBot::Robot.log(:error, 'Captured Timeout on itbit')
    latest = last_order_by(price)
    return latest if latest.present?

    BitexBot::Robot.log(:error, 'Could not find my order')
    raise e
  end

  def transactions
    market.trades.map { |t| transaction_parser(t.symbolize_keys) }
  end

  # We don't need to fetch the list of transaction for itbit since we wont actually use them later.
  def user_transactions
    []
  end

  # [
  #   { total_balance: 0.2e2, currency: :usd, available_balance: 0.1e2 },
  #   { total_balance: 0.0, currency: :xbt, available_balance: 0.0 },
  #   { total_balance: 0.0, currency: :eur, available_balance: 0.0 },
  #   { total_balance: 0.0, currency: :sgd, available_balance: 0.0 }
  # ]
  def balance_summary_parser(balances)
    BalanceSummary.new(balance_parser(balances, base.to_sym), balance_parser(balances, quote.to_sym), 0.5.to_d)
  end

  def wallet
    Itbit::Wallet.all.find { |w| w[:id] == Itbit.default_wallet_id }
  end

  def balance_parser(balances, currency)
    currency_balance = balances.find { |balance| balance[:currency] == currency }
    Balance.new(
      currency_balance[:total_balance].to_d,
      currency_balance[:total_balance].to_d - currency_balance[:available_balance].to_d,
      currency_balance[:available_balance].to_d
    )
  end

  def last_order_by(price)
    Itbit::Order.all.select { |o| o.price == price && (o.created_time - Time.now.to_i).abs < 500 }.first
  end

  # {
  #   bids: [[0.63921e3, 0.195e1], [0.637e3, 0.47e0], [0.63e3, 0.158e1]],
  #   asks: [[0.6424e3, 0.4e0], [0.6433e3, 0.95e0], [0.6443e3, 0.25e0]]
  # }
  def order_book_parser(book)
    OrderBook.new(Time.now.to_i, order_summary_parser(book[:bids]), order_summary_parser(book[:asks]))
  end

  def order_summary_parser(orders)
    orders.map { |order| OrderSummary.new(order[0], order[1]) }
  end

  # <Itbit::Order:
  #   @id='8fd820d3-baff-4d6f-9439-ff03d816c7ce', @wallet_id='b440efce-a83c-4873-8833-802a1022b476', @side=:buy,
  #   @instrument=:xbtusd, @type=:limit, @amount=0.1005e1, @display_amount=0.1005e1, @price=0.1e3,
  #   @volume_weighted_average_price=0.0, @amount_filled=0.0, @created_time=1415290187, @status=:open,
  #   @metadata={foo: 'bar'}, @client_order_identifier='o'
  # >
  def order_parser(order)
    Order.new(order.id, order.side, order.price, order.amount, order.created_time, order)
  end

  # { tid: 601855, price: 0.41814e3, amount: 0.19e-1, date: 1460161126 }
  def transaction_parser(transaction)
    Transaction.new(transaction[:tid], transaction[:price], transaction[:amount], transaction[:date], transaction)
  end

  def market
    "Itbit::#{currency_pair[:name].upcase}MarketData".constantize
  end

  def currency_pair(order_book = '')
    @currency_pair ||= {
      name: order_book,
      base: order_book.slice(0..2),
      quote: order_book.slice(3..6)
    }
  end
end

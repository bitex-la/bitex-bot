# Wrapper implementation for Bitex API.
# https://bitex.la/developers
class BitexApiWrapper < ApiWrapper
  attr_accessor :api_key, :ssl_version, :debug, :sandbox

  def initialize(settings)
    self.api_key = settings.api_key
    self.ssl_version = settings.ssl_version
    self.debug = settings.debug
    self.sandbox = settings.sandbox
  end

  def with_session
    prev_key = Bitex.api_key
    prev_sandbox = Bitex.sandbox
    Bitex.api_key = api_key
    Bitex.sandbox = sandbox
    yield.tap do
      Bitex.api_key = prev_key
      Bitex.sandbox = prev_sandbox
    end
  end

  def profile
    with_session { Bitex::Profile.get }
  end

  def amount_and_quantity(order_id)
    with_session do
      closes = user_transactions.select { |t| t.order_id.to_s == order_id }
      amount = closes.map { |c| c.usd.to_d }.sum.abs
      quantity = closes.map { |c| c.btc.to_d }.sum.abs

      [amount, quantity]
    end
  end

  def balance
    with_session { balance_summary_parser(profile) }
  end

  def find_lost(type, price, _quantity)
    with_session { orders.find { |o| o.type == type && o.price == price && o.timestamp >= 5.minutes.ago.to_i } }
  end

  def order_book
    with_session { order_book_parser(Bitex::MarketData.order_book) }
  end

  def orders
    with_session { Bitex::Order.all.map { |o| order_parser(o) } }
  end

  def send_order(type, price, quantity)
    { sell: Bitex::Ask, buy: Bitex::Bid }[type].create!(BitexBot::Settings.maker.order_book, quantity, price)
  end

  def transactions
    with_session { Bitex::Trade.all.map { |t| transaction_parser(t) } }
  end

  def user_transactions
    with_session { Bitex::Trade.all.map { |trade| user_transaction_parser(trade) } }
  end

  private_class_method

  # {
  #   usd_balance:               10000.00, # Total USD balance.
  #   usd_reserved:               2000.00, # USD reserved in open orders.
  #   usd_available:              8000.00, # USD available for trading.
  #   btc_balance:            20.00000000, # Total BTC balance.
  #   btc_reserved:            5.00000000, # BTC reserved in open orders.
  #   btc_available:          15.00000000, # BTC available for trading.
  #   fee:                            0.5, # Your trading fee (0.5 means 0.5%).
  #   btc_deposit_address: "1XXXXXXXX..."  # Your BTC deposit address.
  # }
  def balance_summary_parser(balances)
    BalanceSummary.new(
      Balance.new(balances[:btc_balance], balances[:btc_reserved], balances[:btc_available]),
      Balance.new(balances[:usd_balance], balances[:usd_reserved], balances[:usd_available]),
      balances[:fee]
    )
  end

  def last_order_by(price)
    orders.select { |o| o.price == price && (o.timestamp - Time.now.to_i).abs < 500 }.first
  end

  # {
  #   bids: [[0.63921e3, 0.195e1], [0.637e3, 0.47e0], [0.63e3, 0.158e1]],
  #   asks: [[0.6424e3, 0.4e0], [0.6433e3, 0.95e0], [0.6443e3, 0.25e0]]
  # }
  def order_book_parser(book)
    OrderBook.new(Time.now.to_i, order_summary_parser(book[:bids]), order_summary_parser(book[:asks]))
  end

  def order_summary_parser(orders)
    orders.map { |order| OrderSummary.new(order[0].to_d, order[1].to_d) }
  end

  # <Bitex::Bid
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @price=0.1e4, @status=:executing, @reason=nil,
  #   @issuer=nil, @amount=0.1e3, @remaining_amount=0.1e2, @produced_quantity=0.0
  # >
  def order_parser(order)
    Order.new(order.id.to_s, order_type(order), order.price, order_amount(order), order.created_at.to_i, order)
  end

  def order_type(order)
    order.is_a?(Bitex::Bid) ? :buy : :sell
  end

  def order_amount(order)
    order.is_a?(Bitex::Bid) ? order.amount : order.quantity
  end

  # [
  #   [1492795215, 80310, 1243.51657154, 4.60321971],
  #   [UNIX timestamp, Transaction ID, Price Paid, Amound Sold]
  # ]
  def transaction_parser(transaction)
    Transaction.new(transaction.id, transaction.price.to_d, transaction.amount.to_d, transaction.created_at.to_i, transaction)
  end

  # <Bitex::Buy:0x007ff9a2979390
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @bid_id=123
  # >
  #
  # <Bitex::Sell:0x007ff9a2978710
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @ask_id=456i
  # >
  def user_transaction_parser(trade)
    UserTransaction.new(
      trade.id, trade.amount, trade.quantity, trade.price, trade.fee, trade_type(trade), trade.created_at.to_i
    )
  end

  def trade_type(trade)
    # ask: 0, bid: 1
    trade.is_a?(Bitex::Buy) ? 1 : 0
  end
end

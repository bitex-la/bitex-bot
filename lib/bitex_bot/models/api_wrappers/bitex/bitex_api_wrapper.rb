# Wrapper implementation for Bitex API.
# https://bitex.la/developers
class BitexApiWrapper < ApiWrapper
  Order = Struct.new(
    :id,        # String
    :type,      # Symbol
    :price,     # Decimal
    :amount,    # Decimal
    :timestamp, # Integer
    :raw        # Actual order object
  ) do
    def method_missing(method_name, *args, &block)
      raw.respond_to?(method_name) ? raw.send(method_name, *args, &block) : super
    end

    def respond_to_missing?(method_name, include_private = false)
      raw.respond_to?(method_name) || super
    end
  end

  attr_accessor :client, :trading_fee

  def initialize(settings)
    self.client = Bitex::Client.new(api_key: settings.api_key, sandbox: settings.sandbox)
    self.trading_fee = settings.trading_fee.to_s.to_d
    currency_pair(settings.order_book)
  end

  # rubocop:disable Metrics/AbcSize
  def amount_and_quantity(order_id)
    closes = user_transactions.select { |t| t.order_id.to_s == order_id }
    amount = closes.map { |c| c.send(currency[:quote]).to_d }.sum.abs
    quantity = closes.map { |c| c.send(currency[:base]).to_d }.sum.abs

    [amount, quantity]
  end
  # rubocop:enable Metrics/AbcSize

  def balance
    BalanceSummary.new(
      balance_parser(coin_wallet),
      balance_parser(cash_wallet),
      trading_fee
    )
  end
  # <Bitex::Resources::Wallets::CoinWallet:
  #   @attributes={
  #     "type"=>"coin_wallets", "id"=>"7347", "balance"=>0.0, "available"=>0.0, "currency"=>"btc",
  #     "address"=>"mu4DKZpadxMgHtRSLwQpaQ9eTTXDEjWZUF", "auto_sell_address"=>"msmet4V5WzBjCR4tr17cxqHKw1LJiRnhHH"
  #   }
  # >
  #
  # <Bitex::Resources::Wallets::CashWallet:
  #   @attributes={
  #     "type"=>"cash_wallets", "id"=>"usd", "balance"=>0.0, "available"=>0.0, "currency"=>"usd"  }
  # >
  def balance_parser(wallet)
    Balance.new(wallet.balance, wallet.balance - wallet.available, wallet.available)
  end

  def find_lost(type, price, _quantity)
    orders.find { |o| o.type == type && o.price == price && o.timestamp >= 5.minutes.ago.to_i }
  end

  def order_book
    order_book_parser(market.order_book)
  end

  def orders
    Bitex::Order.all.map { |o| order_parser(o) }
  end

  def send_order(type, price, quantity, wait = false)
    order = { sell: Bitex::Ask, buy: Bitex::Bid }[type].create!(base_quote.to_sym, quantity, price, wait)
    order_parser(order) if order.present?
  end

  def transactions
    Bitex::Trade.all.map { |t| transaction_parser(t) }
  end

  def user_transactions
    Bitex::Trade.all.map { |trade| user_transaction_parser(trade) }
  end


  def cash_wallet
    client.cash_wallets.find(currency_pair[:quote])
  end

  def coin_wallet
    client.coin_wallets.all.find { |wallet| wallet.currency == currency_pair[:base] }
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

  def market
    @market ||= { btc: Bitex::BitcoinMarketData, bch: Bitex::BitcoinCashMarketData }[currency_pair[:base].to_sym]
  end

  def currency_pair(order_book = '_')
    @currency_pair ||= {
      name: order_book,
      base: order_book.split('_').first,
      quote: order_book.split('_').last
    }
  end
end

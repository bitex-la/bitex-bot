# Wrapper implementation for Bitex API.
# https://bitex.la/developers
class BitexApiWrapper < ApiWrapper
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

  # <
  #   Bitex::Resources::Market:
  #     @attributes={"type"=>"markets", "id"=>"btc_usd"},
  #     asks: [
  #       <Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"4400.0", "price"=>4400.0, "amount"=>20.0}>,
  #       <Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"5000.0", "price"=>5000.0, "amount"=>3.0}>
  #     ],
  #     bids: [
  #       <Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"4200.0", "price"=>4200.0, "amount"=>218.336904745238}>,
  #       <Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"4100.0", "price"=>4100.0, "amount"=>25.007783841463}>
  #     ]
  # >
  def market
    current_market = client.markets.find(orderbook, includes: %i[asks bids])
    OrderBook.new(Time.now.to_i, order_summary(current_market.bids), order_summary(current_market.asks))
  end

  def orderbook
    @orderbook ||= client.orderbooks.find_by_code(currency_pair[:name])
  end

  def order_summary(summary)
    summary.map { |order| OrderSummary.new(order.price, order.amount) }
  end

  def orders
    client.orders.all
      .select { |o| o.orderbook_code == orderbook.code.to_s }
      .map { |o| order_parser(o) }
  end

  # [
  #   <Bitex::Resources::Orders::Order:
  #     @attributes={
  #       "type"=>"bids", "id"=>"4252", "amount"=>1000000.0, "remaining_amount"=>917014.99993, "price"=>4200.0,
  #       "status"=>"executing", "orderbook_code"=>"btc_usd", "timestamp": 1534349999
  #     }
  #   >,
  #   <Bitex::Resources::Orders::Order:
  #     @attributes={
  #       "type"=>"asks", "id"=>"1591", "amount"=>3.0, "remaining_amount"=>3.0, "price"=>5000.0,
  #       "status"=>"executing", "orderbook_code"=>"btc_usd", "timestamp": 1534344859
  #     }
  #   >
  # }
  def order_parser(order)
    type = order.type == 'bids' ? :buy : :sell
    Order.new(order.id, type, order.price, order.amount, DateTime.parse(order.created_at).to_i, order)
  end

  def send_order(type, price, quantity, wait = false)
    order = { sell: Bitex::Ask, buy: Bitex::Bid }[type].create!(base_quote.to_sym, quantity, price, wait)
    order_parser(order) if order.present?
  end

  def transactions
    client.transactions.all(orderbook: orderbook).map { |t| transaction_parser(t) }
  end

  # <Bitex::Resources::Transaction:
  #   @attributes={
  #     "type"=>"transactions", "id"=>"1654", "timestamp"=>1549294667, "price"=>0.44e4, "amount"=>0.22727e-3,
  #     "orderbook_code"=>"btc_usd"
  #   }
  # >
  def transaction_parser(transaction)
    Transaction.new(transaction.id.to_i, transaction.price, transaction.amount, transaction.timestamp, transaction)
  end

  # @param [ApiWrapper::Order]
  def cancel_order(order)
    client.send(order.raw.type).cancel(id: order.id)
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

  def cash_wallet
    client.cash_wallets.find(currency_pair[:quote])
  end

  def coin_wallet
    client.coin_wallets.all.find { |wallet| wallet.currency == currency_pair[:base] }
  end

  def last_order_by(price)
    orders.select { |o| o.price == price && (o.timestamp - Time.now.to_i).abs < 500 }.first
  end

  def currency_pair(order_book = '_')
    @currency_pair ||= {
      name: order_book,
      base: order_book.split('_').first,
      quote: order_book.split('_').last
    }
  end
end

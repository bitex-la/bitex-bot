# Wrapper implementation for Bitex API.
# https://bitex.la/developers
class BitexApiWrapper < ApiWrapper
  attr_accessor :client, :trading_fee

  Order = Struct.new(
    :id,        # String
    :type,      # Symbol <:bid|:ask>
    :price,     # Decimal
    :amount,    # Decimal
    :timestamp, # Integer
    :status,    # :executing, :completed, :cancelled
    :raw        # Actual order object
  ) do
    def method_missing(method_name, *args, &block)
      raw.respond_to?(method_name) ? raw.send(method_name, *args, &block) : super
    end

    def respond_to_missing?(method_name, include_private = false)
      raw.respond_to?(method_name) || super
    end
  end

  def initialize(settings)
    self.client = Bitex::Client.new(api_key: settings.api_key, sandbox: settings.sandbox)
    self.trading_fee = settings.trading_fee.try(:to_d) || 0.to_d
    currency_pair(settings.orderbook_code)
  end

  def user_transactions
    client.trades.all(orderbook: orderbook, days: 30).map { |trade| user_transaction_parser(trade) }
  end

  def amount_and_quantity(order_id)
    trades = user_transactions.select { |t| t.order_id.to_s == order_id }

    [trades.sum(&:fiat).abs, trades.sum(&:crypto).abs]
  end

  def trades
    client.trades.all(orderbook: orderbook, days: 1).map { |trade| user_transaction_parser(trade) }
  end

  # <Bitex::Resources::Trades::Trade:
  #   @attributes={
  #     "type"=>"buys",
  #     "id"=>"161265",
  #     "created_at"=>2019-01-14 13:47:47 UTC,
  #     "coin_amount"=>0.280668e-2,
  #     "cash_amount"=>0.599e5,
  #     "fee"=>0.703e-5,
  #     "price"=>0.2128856417806563e8,
  #     "fee_currency"=>"BTC",
  #     "fee_decimals"=>8,
  #     "orderbook_code"=>:btc_pyg
  #   }
  #
  #   @relationships={
  #     "order"=>{"data"=>{"id"=>"35985296", "type"=>"bids"}}
  #   }
  # >
  # TODO: symbolize and singularize trade type
  def user_transaction_parser(trade)
    UserTransaction.new(
      order_id(trade), trade.cash_amount, trade.coin_amount, trade.price, trade.fee, trade.type, trade.created_at.to_i, trade
    )
  end

  def order_id(trade)
    trade.relationships.order[:data][:id]
  end

  def balance
    BalanceSummary.new(
      balance_parser(client.coin_wallets.find(base)),
      balance_parser(client.cash_wallets.find(quote)),
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

  # <
  #   Bitex::Resources::Market:
  #     @attributes={"type"=>"markets", "id"=>"btc_usd"},
  #     @relationships={:asks<OrderGroup>, :bids<OrderGroup>}
  # >
  def market
    current_market = client.markets.find(orderbook, includes: %i[asks bids])
    OrderBook.new(Time.now.to_i, order_summary(current_market.bids), order_summary(current_market.asks))
  end

  #  <Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"4400.0", "price"=>4400.0, "amount"=>20.0}>,
  def order_summary(summary)
    summary.map { |order| OrderSummary.new(order.price, order.amount) }
  end

  def orderbook
    @orderbook ||= client.orderbooks.find_by_code(currency_pair[:name])
  end

  def orders
    client
      .orders
      .all
      .select { |o| o.orderbook_code == orderbook.code }
      .map { |o| order_parser(o) }
  end

  def bid_by_id(bid_id)
    order_parser(client.bids.find(bid_id))
  rescue StandardError => e
    raise OrderNotFound, e.message
  end

  def ask_by_id(ask_id)
    order_parser(client.asks.find(ask_id))
  rescue StandardError => e
    raise OrderNotFound, e.message
  end

  # [
  #   <Bitex::Resources::Orders::Order:
  #     @attributes={
  #       "type"=>"bids", "id"=>"4252", "amount"=>0.1e7, "remaining_amount"=>0.91701499993e6, "price"=>0.42e4,
  #       "status"=>:executing, "orderbook_code"=>:btc_usd, "created_at": 2000-01-03 00:00:00 UTC
  #     }
  #   >,
  #   <Bitex::Resources::Orders::Order:
  #     @attributes={
  #       "type"=>"asks", "id"=>"1591", "amount"=>0.3e1, "remaining_amount"=>0.3e1, "price"=>0.5e4,
  #       "status"=>:executing, "orderbook_code"=>:btc_usd, "created_at": 2000-01-03 00:00:00 UTC
  #     }
  #   >
  # }
  def order_parser(order)
    type = order.type.singularize.to_sym
    Order.new(order.id, type, order.price, order.amount, order.created_at.to_i, order.status, order)
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
  # TODO all IDs parsed jsonapi must be string
  def transaction_parser(transaction)
    Transaction.new(transaction.id.to_i, transaction.price, transaction.amount, transaction.timestamp, transaction)
  end

  # @param [ApiWrapper::Order]
  def cancel_order(order)
    client.send(order.raw.type).cancel(id: order.id)
  rescue StandardError => e
    # just pass, we'll keep on trying until it's not in orders anymore.
    BitexBot::Robot.log(:error, e.message)
  end

  def last_order_by(price)
    orders.select { |o| o.price == price && (o.timestamp - Time.now.to_i).abs < 500 }.first
  end

  def currency_pair(orderbook_code = '_')
    @currency_pair ||= {
      name: orderbook_code,
      base: orderbook_code.split('_').first,
      quote: orderbook_code.split('_').last
    }
  end

  def send_order(type, price, amount)
    order = { sell: client.asks, buy: client.bids }[type].create(orderbook: orderbook, amount: amount, price: price)
    order_parser(order) if order.present?
  end

  def find_lost(type, price, _quantity)
    orders.find { |o| o.type == type && o.price == price && o.timestamp >= 5.minutes.ago.to_i }
  end
end

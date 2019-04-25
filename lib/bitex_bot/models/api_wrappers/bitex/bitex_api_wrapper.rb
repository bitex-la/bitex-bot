# Wrapper implementation for Bitex API.
# https://bitex.la/developers
class BitexApiWrapper < ApiWrapper
  attr_accessor :client, :trading_fee

  ASK_MIN_AMOUNT = 0.0_001.to_d
  BID_MIN_AMOUNT = 0.1.to_d

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
    trades = user_transactions.select { |trade| trade.order_id == order_id }

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

  # @param [Bitex::Resources::Trades::Trade] trade
  #
  # @return [String]
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

  def order_by_id(type, order_id)
    order_parser(orders_accessor_for(type).find(order_id))
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
    client.transactions.all(orderbook: orderbook).map { |raw| transaction_parser(raw) }
  end

  # <Bitex::Resources::Transaction:
  #   @attributes={
  #     "type"=>"transactions",
  #     "id"=>"1680",
  #     "orderbook_code"=>:btc_usd
  #     "price"=>0.41e4,
  #     "amount"=>0.1e1,
  #     "datetime"=>2019-03-13 17:37:10 UTC,
  #  }
  # >
  def transaction_parser(transaction)
    Transaction.new(transaction.id.to_i, transaction.price, transaction.amount, transaction.datetime.to_i, transaction)
  end

  # @param [ApiWrapper::Order]
  def cancel_order(order)
    client.send(order.raw.type).cancel(id: order.id)
  rescue StandardError => e
    # just pass, we'll keep on trying until it's not in orders anymore.
    BitexBot::Robot.log(:error, e.message)
  end

  def currency_pair(orderbook_code = '_')
    @currency_pair ||= {
      name: orderbook_code,
      base: orderbook_code.split('_').first,
      quote: orderbook_code.split('_').last
    }
  end

  def send_order(type, price, amount)
    order = orders_accessor_for(type).create(orderbook: orderbook, amount: amount, price: price)
    order_parser(order) if order.present?
  end

  def find_lost(type, price, amount, threshold)
    # if order is executing
    order = orders_accessor_for(type)
            .all(orderbook: orderbook)
            .find { |wrapped_order| sought_order?(wrapped_order, price, amount, threshold) }
    return order_parser(order) if order.present?

    # if order is completed
    trade = trades_accessor_for(type)
            .all(orderbook: orderbook)
            .find { |wrapped_trade| sought_trade?(wrapped_trade, price, amount, threshold) }
    return unless trade.present?

    order = orders_accessor_for(type).find(order_id(trade))
    order_parser(order) if order.present?
  end

  def sought_order?(order, price, amount, threshold)
    order.price == price && order.created_at >= threshold && sought_amount?(amount, order.amount)
  end

  def sought_trade?(trade, price, amount, threshold)
    trade_amount = trade.type == 'sells' ? trade.coin_amount : trade.cash_amount

    trade.price == price && trade.created_at >= threshold && sought_amount?(amount, trade_amount)
  end

  def sought_amount?(amount, resource_amount)
    variation = amount - 0.00_000_01

    variation <= resource_amount && resource_amount <= amount
  end

  def trades_accessor_for(type)
    { sell: client.sells, buy: client.buys }[type]
  end

  def orders_accessor_for(type)
    { sell: client.asks, buy: client.bids }[type]
  end

  # Respont to minimun order size to place order.
  #
  # For bids: crypto to obtain must be greather or equal than 0.1
  # For asks: crypto to sell must be greather or equal than 0.0001
  #
  # @param [BigDecimal] amount.
  # @param [BigDecimal] price.
  # @param [Symbol] trade_type. <:buy|:sell>
  #
  # @return [Boolean]
  def enough_order_size?(amount, price, trade_type)
    send("enough_#{trade_type}_size?", amount, price)
  end

  def enough_sell_size?(amount, _price)
    amount >= ASK_MIN_AMOUNT
  end

  def enough_buy_size?(amount, price)
    amount * price >= BID_MIN_AMOUNT
  end
end

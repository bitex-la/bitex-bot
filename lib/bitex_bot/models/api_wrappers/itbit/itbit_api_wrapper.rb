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
    Itbit::XBTUSDMarketData.map { |t| transaction_parser(t) }
  end

  def self.order_book
    Itbit::XBTUSDMarketData.orders.map { |o| order_book_parser(o) }
  end

  def self.balance
    Itbit::Wallet.all.find { |w| w[:id] == Itbit.default_wallet_id }[:balances].map do |balances|
      balance_summary_parser(balances)
    end
  end

  def self.orders
    Itbit::Order.all(status: :open).map { |o| order_parser(o) }
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

  def self.order_parser(o)
    Order.new(o.id, o.type, o.price.to_d, o.amount.to_d, DateTime.parse(o.created_time).to_time.to_i)
  end

  def self.transaction_parser(t)
    Transaction.new(t[:tid].to_i, t[:price].to_d, t[:amount].to_d, t[:date].to_i)
  end

  def self.order_book_parser(ob)
    OrderBook.new(
      Time.now.to_i,
      ob[:bids].map { |bid| OrderSummary.new(bid[0].to_d, bid[1].to_d) },
      ob[:asks].map { |ask| OrderSummary.new(ask[0].to_d, ask[1].to_d) }
    )
  end

  def self.balance_summary_parser(b)
    BalanceSummary.new.tap do |summary|
      btc = b.find { |balance| balance[:currency] == :xbt }
      summary[:btc] =
        Balance.new(
          btc[:total_balance].to_d,
          (btc[:total_balance] - btc[:available_balance]).to_d,
          btc[:available_balance].to_d
      )

      usd = b.find { |balance| balance[:currency] == :usd }
      summary[:usd] =
        Balance.new(
          usd[:total_balance].to_d,
          (usd[:total_balance] - usd[:available_balance]).to_d,
          usd[:available_balance].to_d
      )

      summary[:fee] = 0.5.to_d
    end

  end
end


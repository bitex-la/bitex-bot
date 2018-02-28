class KrakenApiWrapper < ApiWrapper
  MIN_AMOUNT = 0.002

  def self.setup(settings)
    HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
    @settings = settings.kraken
  end

  def self.transactions
    client.public.trades('XBTUSD')[:XXBTZUSD].reverse.map { |t| transaction_parser(t) }
  rescue NoMethodError => e
    retry
  end

  def self.order_book(retries = 20)
    book = client.public.order_book('XBTUSD')[:XXBTZUSD]
    OrderBook.new(
      Time.now.to_i,
      book[:bids].map { |bid| OrderSummary.new(bid[0], bid[1]) },
      book[:asks].map { |ask| OrderSummary.new(ask[0], ask[1]) }
    )
  rescue NoMethodError => e
    retry
  end

  def self.balance
    BalanceSummary.new.tap do |summary|
      open_orders = orders
      balances = client.private.balance

      sell_orders = open_orders.select { |o| o.type == :sell }
      btc_reserved = sell_orders.collect { |o| o.amount - o.executed_amount }.sum
      summary[:btc] = Balance.new(balances['XXBT'].to_d, btc_reserved, balances['XXBT'].to_d - btc_reserved)

      buy_orders = open_orders - sell_orders
      usd_reserved = buy_orders.collect { |o| (o.amount - o.executed_amount) * o.price }.sum
      summary[:usd] = Balance.new(balances['ZUSD'].to_d, usd_reserved, balances['ZUSD'].to_d - usd_reserved)

      summary[:fee] = client.private.trade_volume(pair: 'XBTUSD')[:fees][:XXBTZUSD][:fee].to_d
    end
  rescue KrakenClient::ErrorResponse, Net::ReadTimeout => e
    retry
  end

  def self.orders
    KrakenOrder.open.map { |ko| order_parser(ko) }
  end

  # We don't need to fetch the list of transactions for Kraken
  def self.user_transactions
    []
  end

  def self.enough_order_size?(quantity, price)
    (quantity * price) > MIN_AMOUNT
  end

  def self.send_order(type, price, quantity)
    KrakenOrder.create!(type, price, quantity)
  end

  def self.find_lost(type, price, quantity)
    KrakenOrder.find_lost(type, price, quantity)
  end

  def self.amount_and_quantity(order_id, transactions)
    KrakenOrder.amount_and_quantity(order_id, transactions)
  end

  def self.client
    @client ||= KrakenClient.load(@settings)
  end

  private

  def self.order_parser(o)
    Order.new(o.id, o.type, o.price.to_d, o.amount.to_d, DateTime.parse(o.datetime).to_time.to_i)
  end

  def self.transaction_parser(t)
    Transaction.new(t[2].to_s, t[0].to_d, t[1].to_d, t[2].to_i)
  end

  def self.balance_summary_parser(b)
    BalanceSummary.new(
      Balance.new(b['btc_balance'].to_d, b['btc_reserved'].to_d, b['btc_available'].to_d),
      Balance.new(b['usd_balance'].to_d, b['usd_reserved'].to_d, b['usd_available'].to_d),
      b['fee'].to_d
    )
  end

  def self.order_parser(o)
    Order.new(o.id, o.type, o.price, o.amount, o.datetime)
  end
end

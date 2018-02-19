class KrakenApiWrapper < ApiWrapper
  MIN_AMOUNT = 0.002

  def self.setup(settings)
    HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
    @settings = settings.kraken
  end

  def self.transactions
    client.public.trades('XBTUSD')[:XXBTZUSD].reverse.collect do |t|
      Hashie::Mash.new(tid: t[2].to_s, price: t[0], amount: t[1], date: t[2])
    end
  rescue NoMethodError => e
    retry
  end

  def self.order_book(retries = 20)
    {
      'bids' => book[:bids].collect { |b| [ b[0], b[1] ] },
      'asks' => book[:asks].collect { |a| [ a[0], a[1] ] }
    }
  rescue NoMethodError => e
    retry
  end

  def self.balance
    balances = client.private.balance
    sell_orders = open_orders.select { |o| o.type == :sell }
    btc_reserved = sell_orders.collect { |o| o.amount - o.executed_amount }.sum
    buy_orders = open_orders - sell_orders
    usd_reserved = buy_orders.collect { |o| (o.amount - o.executed_amount) * o.price }.sum
    {
      'btc_balance' => balances['XXBT'].to_d,
      'btc_reserved' => btc_reserved,
      'btc_available' => balances['XXBT'].to_d - btc_reserved,
      'usd_balance' => balances['ZUSD'].to_d,
      'usd_reserved' => usd_reserved,
      'usd_available' => balances['ZUSD'].to_d - usd_reserved,
      'fee' => client.private.trade_volume(pair: 'XBTUSD')[:fees][:XXBTZUSD][:fee].to_d
    }
  rescue KrakenClient::ErrorResponse, Net::ReadTimeout => e
    retry
  end

  def self.enough_order_size?(quantity, price)
    quantity >= MIN_AMOUNT
  end

  def self.orders
    KrakenOrder.open
  end

  # We don't need to fetch the list of transactions for Kraken
  def self.user_transactions
    []
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

  private

  def self.client
    @client ||= KrakenClient.load(@settings)
  end

  def self.book
    @book ||= client.public.order_book('XBTUSD')[:XXBTZUSD]
  end

  def self.open_orders
    @open_orders ||= KrakenOrder.open
  end
end

# Wrapper implementation for Kraken API.
# https://www.kraken.com/en-us/help/api
class KrakenApiWrapper < ApiWrapper
  attr_accessor :api_key, :api_secret, :client

  MIN_AMOUNT = 0.002

  def initialize(settings)
    self.api_key = settings.api_key
    self.api_secret = settings.api_secret
    setup
  end

  def setup
    KrakenOrder.api_wrapper = self
    self.client ||= KrakenClient.load(api_key: api_key, api_secret: api_secret)
    HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
  end

  def amount_and_quantity(order_id)
    KrakenOrder.amount_and_quantity(order_id)
  end

  def balance
    balance_summary_parser(client.private.balance)
  rescue KrakenClient::ErrorResponse, Net::ReadTimeout
    retry
  end

  def enough_order_size?(quantity, _price)
    quantity >= MIN_AMOUNT
  end

  def find_lost(type, price, quantity)
    order = KrakenOrder.find_lost(type, price, quantity)
    order_parser(order) if order.present?
  end

  def order_book
    order_book_parser(client.public.order_book(currency_pair[:altname])[currency_pair[:name]])
  rescue NoMethodError
    retry
  end

  def orders
    KrakenOrder.open.map { |o| order_parser(o) }
  end

  def send_order(type, price, quantity)
    order = KrakenOrder.create!(type, price, quantity)
    order_parser(order) if order.present?
  end

  def transactions
    client.public.trades(currency_pair[:altname])[currency_pair[:name]].reverse.map { |t| transaction_parser(t) }
  rescue NoMethodError
    retry
  end

  # We don't need to fetch the list of transactions for Kraken
  def user_transactions
    []
  end

  # { ZEUR: '1433.0939', XXBT: '0.0000000000', 'XETH': '99.7497224800' }
  # rubocop:disable Metrics/AbcSize
  def balance_summary_parser(balances)
    open_orders = KrakenOrder.open
    BalanceSummary.new(
      balance_parser(balances, currency_pair[:base], crypto_reserved(open_orders)),
      balance_parser(balances, currency_pair[:quote], fiat_reserved(open_orders)),
      client.private.trade_volume(pair: currency_pair[:altname])[:fees][currency_pair[:name]][:fee].to_d
    )
  end
  # rubocop:enable Metrics/AbcSize

  def balance_parser(balances, currency, reserved)
    Balance.new(balances[currency].to_d, reserved, balances[currency].to_d - reserved)
  end

  def crypto_reserved(open_orders)
    orders_by(open_orders, :sell).sum { |o| (o.amount - o.executed_amount).to_d }
  end

  def fiat_reserved(open_orders)
    orders_by(open_orders, :buy).sum { |o| (o.amount - o.executed_amount) * o.price.to_d }
  end

  def orders_by(open_orders, order_type)
    open_orders.select { |o| o.type == order_type }
  end

  # {
  #   'asks': [['204.52893', '0.010', 1440291148], ['204.78790', '0.312', 1440291132]],
  #   'bids': [['204.24000', '0.100', 1440291016], ['204.23010', '0.312', 1440290699]]
  # }
  def order_book_parser(book)
    OrderBook.new(Time.now.to_i, order_summary_parser(book[:bids]), order_summary_parser(book[:asks]))
  end

  def order_summary_parser(stock_market)
    stock_market.map { |stock| OrderSummary.new(stock[0].to_d, stock[1].to_d) }
  end

  # <KrakenOrder:0x007faf255382d0 @id="OGZ3HI-5I322-OIOV52", @type=:sell, @datetime=1546971756, @amount=0.248752e-2,
  #  @executed_amount=0.248752e-2, @price=0.40025e4, @avg_price=0.40074e4>
  def order_parser(order)
    Order.new(order.id, order.type, order.price, order.amount, order.datetime, order)
  end

  # [
  #   ['price', 'amount', 'timestamp', 'buy/sell', 'market/limit', 'miscellaneous']
  #   ['202.51626', '0.01440000', 1440277319.1922, 'b', 'l', ''],
  #   ['202.54000', '0.10000000', 1440277322.8993, 'b', 'l', '']
  # ]
  def transaction_parser(transaction)
    Transaction.new(transaction[2].to_i, transaction[0].to_d, transaction[1].to_d, transaction[2].to_i)
  end

  # {
  #   'XBTUSD' => {
  #     'altname' => 'XBTUSD',
  #     'aclass_base' => 'currency',
  #     'base' => 'XXBT',
  #     'aclass_quote' => 'currency',
  #     'quote' => 'ZUSD',
  #     'lot' => 'unit',
  #     'pair_decimals' => 1,
  #     'lot_decimals' => 8,
  #     'lot_multiplier' => 1,
  #     'leverage_buy' => [2, 3, 4, 5],
  #     'leverage_sell' => [2, 3, 4, 5],
  #     'fees' => [[0, 0.26], .., [250_000, 0.2]],
  #     'fees_maker' => [[0, 0.16], .., [250_000, 0.1]],
  #     'fee_volume_currency' => 'ZUSD',
  #     'margin_call' => 80,
  #     'margin_stop' => 40
  #   }
  # }
  def currency_pair
    @currency_pair ||= client.public.asset_pairs.map do |currency_pair, data|
      [data['altname'], data.merge(name: currency_pair).with_indifferent_access]
    end.to_h[BitexBot::Settings.taker_settings.order_book.upcase]
  end
end

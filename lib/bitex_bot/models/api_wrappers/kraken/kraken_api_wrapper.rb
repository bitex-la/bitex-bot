##
# Wrapper implementation for Kraken API.
# https://www.kraken.com/en-us/help/api
#
class KrakenApiWrapper < ApiWrapper
  MIN_AMOUNT = 0.002

  class << self
    def setup(settings)
      HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
      @settings = settings.kraken
    end

    def client
      @client ||= KrakenClient.load(@settings)
    end

    def amount_and_quantity(order_id, transactions)
      KrakenOrder.amount_and_quantity(order_id, transactions)
    end

    def balance
      balance_summary_parser(client.private.balance)
    rescue KrakenClient::ErrorResponse, Net::ReadTimeout
      retry
    end

    def enough_order_size?(quantity, price)
      (quantity * price) > MIN_AMOUNT
    end

    def find_lost(type, price, quantity)
      KrakenOrder.find_lost(type, price, quantity)
    end

    def order_book
      order_book_parser(client.public.order_book('XBTUSD')[:XXBTZUSD])
    rescue NoMethodError
      retry
    end

    def orders
      KrakenOrder.open.map { |ko| order_parser(ko) }
    end

    def send_order(type, price, quantity)
      KrakenOrder.create!(type, price, quantity)
    end

    def transactions
      client.public.trades('XBTUSD')[:XXBTZUSD].reverse.map { |t| transaction_parser(t) }
    rescue NoMethodError
      retry
    end

    # We don't need to fetch the list of transactions for Kraken
    def user_transactions
      []
    end

    private

    # { ZEUR: '1433.0939', XXBT: '0.0000000000', 'XETH': '99.7497224800' }
    def balance_summary_parser(balances)
      open_orders = KrakenOrder.open
      self::BalanceSummary.new(
        balance_parser(balances, :XXBT, btc_reserved(open_orders)),
        balance_parser(balances, :ZUSD, usd_reserved(open_orders)),
        client.private.trade_volume(pair: 'XBTUSD')[:fees][:XXBTZUSD][:fee].to_d
      )
    end

    def balance_parser(balances, currency, reserved)
      self::Balance.new(balances[currency].to_d, reserved, balances[currency].to_d - reserved)
    end

    def btc_reserved(open_orders)
      orders_by(open_orders, :sell).map { |o| (o.amount - o.executed_amount).to_d }.sum
    end

    def usd_reserved(open_orders)
      orders_by(open_orders, :buy).map { |o| (o.amount - o.executed_amount) * o.price.to_d }.sum
    end

    def orders_by(open_orders, order_type)
      open_orders.select { |o| o.type == order_type }
    end

    # {
    #   'asks': [['204.52893', '0.010', 1440291148], ['204.78790', '0.312', 1440291132]],
    #   'bids': [['204.24000', '0.100', 1440291016], ['204.23010', '0.312', 1440290699]]
    # }
    def order_book_parser(book)
      self::OrderBook.new(Time.now.to_i, order_summary_parser(book[:bids]), order_summary_parser(book[:asks]))
    end

    def order_summary_parser(stock_market)
      stock_market.map { |stock| self::OrderSummary.new(stock[0].to_d, stock[1].to_d) }
    end

    # <KrakenOrder: @id='O5TDV2-WDYB2-6OGJRD', @type=:buy, @price='1.01', @amount='1.00000000', @datetime='2013-09-26 23:15:04'>
    def order_parser(order)
      self::Order.new(order.id.to_s, order.type, order.price, order.amount, order.datetime)
    end

    # [
    #   ['price', 'amount', 'timestamp', 'buy/sell', 'market/limit', 'miscellaneous']
    #   ['202.51626', '0.01440000', 1440277319.1922, 'b', 'l', ''],
    #   ['202.54000', '0.10000000', 1440277322.8993, 'b', 'l', '']
    # ]
    def transaction_parser(transaction)
      self::Transaction.new(transaction[2].to_i, transaction[0].to_d, transaction[1].to_d, transaction[2].to_i)
    end
  end
end

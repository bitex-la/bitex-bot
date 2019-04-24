module BitexBot
  module Exchanges
    # Wrapper implementation for Itbit API.
    # https://api.itbit.com/docs
    class Itbit < Exchange
      attr_accessor :client_order_id

      def initialize(settings)
        ::Itbit.tap do |conf|
          conf.client_key = settings.client_key
          conf.secret = settings.secret
          conf.user_id = settings.user_id
          conf.default_wallet_id = settings.default_wallet_id
        end

        self.currency_pair = Hashie::Mash.new(
          code: settings.orderbook_code,
          base: settings.orderbook_code.slice(0..2),
          quote: settings.orderbook_code.slice(3..6)
        )
      end

      def balance
        balance_summary_parser(wallet[:balances])
      end

      def market
        orderbook_parser(market_accessor.orders)
      end

      def orders
        ::Itbit::Order
          .all(instrument: currency_pair.code, status: :open)
          .map { |raw| order_parser(raw) }
      end

      def cancel_order(order)
        order.raw.cancel!
      end

      def transactions
        market_accessor.trades.map { |raw| transaction_parser(raw.symbolize_keys) }
      end

      def amount_and_quantity(order_id)
        raw_order = ::Itbit::Order.find(order_id)
        amount = raw_order.volume_weighted_average_price * raw_order.amount_filled
        quantity = raw_order.amount_filled

        [amount, quantity]
      end

      private

      # @param [String] id
      #
      # @returns [Array(5)<Hash(:total_balance, :currency, :available_balance)>]
      def wallet(id: ::Itbit.default_wallet_id)
        ::Itbit::Wallet.all.find { |w| w[:id] == id }
      end

      # @param [Array(5)<Hash(:total_balance, :currency, :available_balance)>] raw_balances.
      #
      # @returns [BitexBot::Exchanges::BalanceSummary]
      def balance_summary_parser(raw)
        BalanceSummary.new(
          balance_parser(raw, currency_pair.base),
          balance_parser(raw, currency_pair.quote),
          0.5.to_d
        )
      end

      # @param [Array(5)<Hash(:total_balance, :currency, :available_balance)>] raw_balances.
      # @param [Symbol] currency. <:eth|:xbt|:usd|:eur|:sgd>
      #
      # @returns [BitexBot::Exchanges::Balance]
      def balance_parser(raws, currency)
        raw = raws.find { |r| r[:currency] == currency.to_sym }
        Balance.new(
          raw[:total_balance].to_d,
          raw[:total_balance].to_d - raw[:available_balance].to_d,
          raw[:available_balance].to_d
        )
      end

      def market_accessor
        @market_accessor ||= "::Itbit::#{currency_pair.code.upcase}MarketData".constantize
      end

      # @param [
      #   Hash(
      #     bids: Array<Array[BigDecimal, BigDeceimal]>,
      #     asks: Array<Array[BigDecimal, BigDeceimal]>
      #   )
      # ] raw.
      #
      # @returns [BitexBot::Exchanges::Orderbook]
      def orderbook_parser(raw)
        Orderbook.new(Time.now.to_i, order_summary_parser(raw[:bids]), order_summary_parser(raw[:asks]))
      end

      # @param [Array<Array<BigDecimal, BigDecimal>>] raws.
      #
      # @returns [Array<BitexBot::Exchanges::OrderSummary>]
      def order_summary_parser(raws)
        raws.map { |raw| OrderSummary.new(raw[0], raw[1]) }
      end

      # @param [::Itbit::Order] raw.
      #   <Itbit::Order:
      #     @id='8fd820d3-baff-4d6f-9439-ff03d816c7ce', @wallet_id='b440efce-a83c-4873-8833-802a1022b476', @side=:buy,
      #     @instrument=:xbtusd, @type=:limit, @amount=0.1005e1, @display_amount=0.1005e1, @price=0.1e3,
      #     @volume_weighted_average_price=0.0, @amount_filled=0.0, @created_time=1415290187, @status=:open,
      #     @metadata={foo: 'bar'}, @client_order_identifier='o'
      #   >
      #
      # @returns [BitexBot::Exchanges::Order]
      def order_parser(raw)
        Order.new(raw.id, order_types[raw.side], raw.price, raw.amount, raw.created_time, order_statuses[raw.status], raw)
      end

      def order_statuses
        @order_statuses ||=
          Hash.new(:undefined).merge(open: :executing, filled: :completed, cancelled: :cancelled, rejected: :cancelled)
      end

      def order_types
        @order_types ||= Hash.new(:undefined).merge(buy: :bid, sell: :ask)
      end

      # @param [Hash(tid: Integer, price: BigDecimal, amount: BigDecimal, date: Integer)] raw_trade.
      #
      # @returns [BitexBot::Exchanges::Transaction]
      def transaction_parser(raw)
        Transaction.new(raw[:tid], raw[:price], raw[:amount], raw[:date], raw)
      end

      # @param [Symbol] type <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      #
      # @return [BitexBot::Exchanges::Order]
      def send_order(type, price, amount)
        price = rounded_price(type, price)

        raw = ::Itbit::Order.create!(
          type,
          currency_pair.code,
          amount.round(4),
          price.round(2),
          wait: true,
          currency: currency_pair.base,
          client_order_identifier: client_order_id
        )

        order_parser(raw) if raw.present?
      end

      # Itbit only allows placing orders with cents on the scale of 0.0, 0.25, 0.5, 0.75.
      #
      # @param [Simbol] type. <:buy|:sell>
      # @param [BigDecimal] price.
      #
      # @return [BigDecimal]
      def rounded_price(type, price)
        price -= price % 0.25
        type == :buy ? price : price + 0.25
      end

      def client_order_id
        @client_order_id = 1.second.from_now.utc.strftime('%N').crypt(::Itbit.user_id)
      end

      # Don't care about order details, it will be searched by previous client order id setted when it tried to place order.
      #
      # @returns [BitexBot::Exchanges::Order]
      def find_lost(*)
        raw = ::Itbit::Order.all.find { |raw_order| raw_order.client_order_identifier == client_order_id }

        order_parser(raw) if raw.present?
      end
    end
  end
end

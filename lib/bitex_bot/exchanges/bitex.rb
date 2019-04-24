# Wrapper implementation for Bitex API.
# https://bitex.la/developers
module BitexBot
  module Exchanges
    class Bitex < Exchange
      attr_accessor :client, :trading_fee

      MIN_ASK_AMOUNT = 0.0_001.to_d
      MIN_BID_AMOUNT = 0.1.to_d

      def initialize(settings)
        self.client = ::Bitex::Client.new(api_key: settings.api_key, sandbox: settings.sandbox)
        self.trading_fee = settings.trading_fee.to_d
        self.currency_pair = Hashie::Mash.new(
          code: settings.orderbook_code.to_sym,
          base: settings.orderbook_code.split('_').first.to_sym,
          quote: settings.orderbook_code.split('_').last.to_sym
        )
      end

      def balance
        BalanceSummary.new(
          balance_parser(client.coin_wallets.find(currency_pair.base)),
          balance_parser(client.cash_wallets.find(currency_pair.quote)),
          trading_fee
        )
      end

      def market
        current_market = client.markets.find(orderbook, includes: %i[asks bids])
        Orderbook.new(Time.now.to_i, order_summary_parser(current_market.bids), order_summary_parser(current_market.asks))
      end

      def orders
        client
          .orders
          .all
          .map { |raw| order_parser(raw) if raw.orderbook_code == orderbook.code }
          .compact
      end

      def cancel_order(order)
        client.send(order.raw.type).cancel(id: order.id)
      end

      def transactions
        client.transactions.all(orderbook: orderbook).map { |raw| transaction_parser(raw) }
      end

      def user_transactions(days: 30)
        client.trades.all(orderbook: orderbook, days: days).map { |raw| user_transaction_parser(raw) }
      end

      def amount_and_quantity(order_id)
        trades = user_transactions.select { |trade| trade.order_id == order_id }

        [trades.sum(&:fiat).abs, trades.sum(&:crypto).abs]
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
      def enough_order_size?(amount, _price, trade_type)
        send("enough_#{trade_type}_size?", amount)
      end

      def trades
        user_transactions(days: 1)
      end

      def order_by_id(type, order_id)
        raw = orders_accessors[type].find(order_id)
        order_parser(raw) if raw.present?
      end

      private

      # @param [::Bitex::Resources::Wallets::Wallet] raw.
      #
      # <::Bitex::Resources::Wallets::CoinWallet:
      #   @attributes={
      #     "type"=>"coin_wallets", "id"=>"7347", "balance"=>0.0, "available"=>0.0, "currency"=>"btc",
      #     "address"=>"mu4DKZpadxMgHtRSLwQpaQ9eTTXDEjWZUF", "auto_sell_address"=>"msmet4V5WzBjCR4tr17cxqHKw1LJiRnhHH"
      #   }
      # >
      #
      # <::Bitex::Resources::Wallets::CashWallet:
      #   @attributes={
      #     "type"=>"cash_wallets", "id"=>"usd", "balance"=>0.0, "available"=>0.0, "currency"=>"usd"  }
      # >
      #
      # @returns [BitexBot::Exchanges::Balance]
      def balance_parser(raw)
        Balance.new(raw.balance, raw.balance - raw.available, raw.available)
      end

      # @param [Array<::Bitex::Resources::OrderGroup>] raws.
      #
      # <::Bitex::Resources::OrderGroup:@attributes={"type"=>"order_groups", "id"=>"4400.0", "price"=>4400.0, "amount"=>20.0}>
      #
      # @returns [Array<BitexBot::Exchanges::OrderSummary>]
      def order_summary_parser(raws)
        raws.map { |raw| OrderSummary.new(raw.price, raw.amount) }
      end

      # returns [::Bitex::Resources::Orderbook]
      def orderbook
        @orderbook ||= client.orderbooks.find_by_code(currency_pair.code)
      end

      # @param [::Bitex::Resources::Orders::Order] raw.
      #
      # <::Bitex::Resources::Orders::Order:
      #   @attributes={
      #     "type"=>"asks", "id"=>"1591", "amount"=>0.3e1, "remaining_amount"=>0.3e1, "price"=>0.5e4,
      #     "status"=>:executing, "orderbook_code"=>:btc_usd, "created_at": 2000-01-03 00:00:00 UTC
      #   }
      # >
      #
      # @returns [BitexBot::Exchanges::Bitex::Order]
      def order_parser(raw)
        Order.new(raw.id, order_types[raw.type], raw.price, raw.amount, raw.created_at.to_i, raw.status, raw)
      end

      def order_types
        @order_types ||= Hash.new(:undefined).merge('asks' => :ask, 'bids' => :bid)
      end

      # @param [Symbol] type. <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      #
      # @returns [BitexBot::Exchanges::Bitex::Order]
      def send_order(type, price, amount)
        order = orders_accessors[type].create(orderbook: orderbook, amount: amount, price: price)
        order_parser(order) if order.present?
      end

      def orders_accessors
        @orders_accessors ||= { sell: client.asks, buy: client.bids }
      end

      # Try to search a lost order in open orders,
      # unless be in, us can think that was executed, then try to search as transaction.
      # If it finds the transaction that belongs according to the price, the amount, and the time limit,
      # then we get order_id from it and then search it by ID.
      # For this use case, just only needs the order_id, but nevertheless returns a Exchanges::Order struct type.
      #
      # @param [Symbol] type. <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      # @param [Time] threshold. UTC
      #
      # @returns [BitexBot::Exchanges::Bitstamp::Order]
      def find_lost(type, price, amount, threshold) # rubocop:disable Metrics/AbcSize
        order = orders_accessors[type]
                .all(orderbook: orderbook)
                .find { |wrapped_order| sought_order?(wrapped_order, price, amount, threshold) }
        return order_parser(order) if order.present?

        trade = trades_accessors[type]
                .all(orderbook: orderbook)
                .find { |wrapped_trade| sought_trade?(wrapped_trade, price, amount, threshold) }
        return unless trade.present?

        order = orders_accessors[type].find(order_id(trade))
        order_parser(order) if order.present?
      end

      def trades_accessors
        @trades_accessors ||= { sell: client.sells, buy: client.buys }
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

      # @param [Bitex::Resources::Transaction] raw.
      #
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
      #
      # @returns [BitexBot::Exchanges::Transaction]
      def transaction_parser(raw)
        Transaction.new(raw.id, raw.price, raw.amount, raw.datetime.to_i, raw)
      end

      # @param [::Bitex::Resources::Trades::Trade] raw.
      #
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
      #
      # @returns [BitexBot::Exchanges::UserTransaction]
      def user_transaction_parser(raw)
        UserTransaction.new(
          order_id(raw),
          raw.cash_amount,
          raw.coin_amount,
          raw.price,
          raw.fee,
          trade_types[raw.type],
          raw.created_at.to_i,
          raw
        )
      end

      def order_id(raw_trade)
        raw_trade.relationships.order[:data][:id]
      end

      def trade_types
        @trade_types ||= Hash.new(:undefinded).merge('sells' => :sell, 'buys' => :buy)
      end

      def enough_sell_size?(amount)
        amount >= MIN_ASK_AMOUNT
      end

      def enough_buy_size?(amount)
        amount >= MIN_BID_AMOUNT
      end
    end
  end
end

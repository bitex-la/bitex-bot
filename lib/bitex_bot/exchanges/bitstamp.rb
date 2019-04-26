module BitexBot
  module Exchanges
    # Wrapper implementation for Bitstamp API.
    # https://www.bitstamp.net/api/
    class Bitstamp < Exchange
      def initialize(settings)
        ::Bitstamp.setup do |config|
          config.key = settings.api_key
          config.secret = settings.secret
          config.client_id = settings.client_id
        end

        self.currency_pair = Hashie::Mash.new(
          code: settings.orderbook_code,
          base: settings.orderbook_code.slice(0..2),
          quote: settings.orderbook_code.slice(3..5)
        )
      end

      def balance
        balance_summary_parser(::Bitstamp.balance(currency_pair.code).symbolize_keys)
      end

      def market
        orderbook_parser(::Bitstamp.order_book(currency_pair.code).symbolize_keys)
      end

      def orders
        ::Bitstamp
          .orders
          .all(currency_pair: currency_pair.code)
          .map { |raw| order_parser(raw) }
      end

      def cancel_order(order)
        ActiveSupport::JSON.decode(order.raw.cancel!).symbolize_keys
      end

      def transactions
        ::Bitstamp
          .transactions(currency_pair.code)
          .map { |raw| transaction_parser(raw) }
      end

      def user_transactions
        ::Bitstamp
          .user_transactions
          .all(currency_pair: currency_pair.code)
          .map { |raw| user_transaction_parser(raw) }
      end

      def amount_and_quantity(order_id)
        trades = user_transactions.select { |trade| trade.order_id == order_id }

        [trades.sum(&:fiat).abs, trades.sum(&:crypto).abs]
      end

      private

      # @param [
      #   Hash(
      #     btc_reserved: String, btc_available: String, btc_balance: String,
      #     ...,
      #     fee: String
      #   )
      # ] raws.
      #
      # @returns [BitexBot::Exchanges::BalanceSummary]
      def balance_summary_parser(raws)
        BalanceSummary.new(
          balance_parser(raws, currency_pair.base),
          balance_parser(raws, currency_pair.quote),
          raws[:fee].to_d
        )
      end

      # @param [
      #   Hash(
      #     btc_reserved: String, btc_available: String, btc_balance: String,
      #     ...,
      #     fee: String
      #   )
      # ] raws.
      # @param [Symbol] currency
      #
      # @returns [BitexBot::Exchanges::Balance]
      def balance_parser(raws, currency)
        Balance.new(
          raws["#{currency}_balance".to_sym].to_d,
          raws["#{currency}_reserved".to_sym].to_d,
          raws["#{currency}_available".to_sym].to_d
        )
      end

      # @param [
      #   Hash(
      #     :timestamp,
      #     bids: <Array<BigDecimal, BigDecimal>,
      #     asks: <Array<BigDecimal, BigDecimal>
      #   )
      # ] raw.
      #
      # {
      #   timestamp: '1380237884',
      #   bids: [['124.55', '1.58057006'], ['124.40', '14.91779125']],
      #   asks: [['124.56', '0.81888247'], ['124.57', '0.81078911']]
      # }
      #
      # @returns [BitexBot::Exchanges::Orderbook]
      def orderbook_parser(raw)
        Orderbook.new(raw[:timestamp].to_i, order_summary_parser(raw[:bids]), order_summary_parser(raw[:asks]))
      end

      # @param [Array<::Bitstamp::Order>] raws.
      #
      # @returns [Array<BitexBot::Exchanges::Bitstamp::Order>]
      def order_summary_parser(raws)
        raws.map { |raw| OrderSummary.new(raw[0].to_d, raw[1].to_d) }
      end

      # @param [::Bitstamp::Order] raw.
      # @param [Symbol] status. Optional: <:executing|:cancelled|:finalised>
      #
      # <Bitstamp::Order @id='76', @type='0', @price='1.1', @amount='1.0', @datetime='2013-09-26 23:15:04'>
      #
      # @returns [BitexBot::Exchanges::Bitstamp::Order]
      def order_parser(raw, status: :executing)
        Order.new(raw.id, order_types[raw.type], raw.price.to_d, raw.amount.to_d, raw.datetime.to_datetime.to_i, status, raw)
      end

      def order_types
        @order_types ||= Hash.new(:undefined).merge('0' => :bid, '1' => :ask, buy: :bid, sell: :ask)
      end

      # @param [Symbol] type. <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      #
      # @returns [BitexBot::Exchanges::Bitstamp::Order]
      def send_order(type, price, amount)
        raw = ::Bitstamp.orders.send(
          type,
          currency_pair: currency_pair.code,
          amount: amount.truncate(4),
          price: price.truncate(2)
        )

        return unless raw.present?

        raise OrderError, raw.reason['__all__'].join if raw.status.present? && raw.status.inquiry.error?

        order_parser(raw)
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
      def find_lost(type, price, amount, threshold)
        amount = amount.truncate(4)
        price = price.truncate(2)

        order = find_open_order(type, threshold, price, amount)
        return order if order.present?

        trade = find_trade_order(threshold, price, amount)
        return unless trade.present?

        Order.new(trade.order_id, order_types[type], price, amount, trade.timestamp, :completed, :not_found)
      end

      # @param [Symbol] type. <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      # @param [Time] threshold. UTC
      #
      # @returns [BitexBot::Exchanges::Bitstamp::Order]
      def find_open_order(type, threshold, price, amount)
        orders.find do |order|
          order.type == order_types[type] &&
            order.timestamp >= threshold.to_i &&
            order.price == price &&
            order.amount == amount
        end
      end

      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      # @param [Time] threshold. UTC
      #
      # @returns [BitexBot::Exchanges::UserTransaction]
      def find_trade_order(threshold, price, amount)
        user_transactions.find do |trade|
          trade.raw.type == '2' && # 0: deposit, 1: withdrawal, 2: market trade, 14: sub account transfer
            trade.timestamp >= threshold.to_i &&
            trade.price == price &&
            trade.fiat == amount ||
            trade.crypto == amount
        end
      end

      # @param [::Bitstamp::Transaction] raw.
      #
      # <Bitstamp::Transactions: @tid='1469074', @price='126.95', @amount='1.10000000', @date='1380648951'>
      #
      # @returns [BitexBot::Exchanges::Transaction]
      def transaction_parser(raw)
        Transaction.new(raw.tid, raw.price.to_d, raw.amount.to_d, raw.date.to_i, raw)
      end

      # @params [::Bitstamp::UserTransaction] raw.
      #
      # <Bitstamp::UserTransaction:
      #   @usd='-373.51', @btc='3.00781124', @btc_usd='124.18', @order_id=7623942, @fee='1.50', @type=2, @id=1444404,
      #   @datetime='2013-09-26 13:28:55' # It comes on UTC
      # >
      #
      # @returns [BitexBot::Exchanges::UserTransaction]
      def user_transaction_parser(raw) # rubocop:disable Metrics/AbcSize
        UserTransaction.new(
          raw.order_id.to_s,
          raw.send(currency_pair.quote).to_d,
          raw.send(currency_pair.base).to_d,
          raw.send("#{currency_pair.base}_#{currency_pair.quote}").to_d,
          raw.fee.to_d,
          order_types[raw.type],
          Time.parse(raw.datetime).to_i,
          raw
        )
      end
    end
  end
end

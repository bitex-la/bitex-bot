module BitexBot
  module Exchanges
    # Wrapper implementation for Kraken API.
    # https://www.kraken.com/en-us/help/api
    class Kraken < Exchange
      require 'kraken_client'

      attr_accessor :client, :client_order_id

      MIN_AMOUNT = 0.002.to_d

      def initialize(settings)
        HTTParty::Basement.headers('User-Agent' => BitexBot.user_agent)
        self.client ||= KrakenClient.load(api_key: settings.api_key, api_secret: settings.api_secret)
        @orderbook_code = settings.orderbook_code
      end

      def balance
        balance_summary_parser(client.private.balance)
      rescue KrakenClient::ErrorResponse, Net::ReadTimeout
        retry
      end

      def market
        orderbook_parser(client.public.order_book(currency_pair.altname)[currency_pair.code])
      end

      def orders
        client
          .private.open_orders[:open]
          .select { |_, raw| raw[:descr][:pair] == currency_pair.altname }
          .map { |id, raw| order_parser(id, raw.deep_symbolize_keys) }
      end

      def cancel_order(order)
        client.private.cancel_order(txid: order.id)
      end

      def enough_order_size?(amount, _price, _trade_type)
        amount >= MIN_AMOUNT
      end

      def transactions
        client
          .public.trades(currency_pair.altname)[currency_pair.code]
          .reverse
          .map { |raw| transaction_parser(raw) }
      end

      def amount_and_quantity(order_id)
        order = order_by_id(order_id)
        quantity = order.raw.vol_exec.to_d
        amount = order.raw.price.to_d * quantity

        [amount, quantity]
      end

      private

      # This accessor si custom for this exchange, uses its own nomenclature.
      #
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
      #
      # @returns [Hashie::Mash(:code, :base, :quote, :altname)]
      def currency_pair
        @currency_pair ||= Hashie::Mash.new(
          client.public.asset_pairs.map do |code, data|
            [data[:altname], data.slice(:altname, :base, :quote).merge(code: code)]
          end.to_h[@orderbook_code.upcase]
        )
      end

      # @param [Array<Hash(String:id, Hash:data)>] raw_orders.
      #
      # @returns [Array<BitexBot::Exchange::Order>]
      def parse_orders(raw_orders)
        raw_orders
      end

      # @param [String>] id. Raw order ID.
      # @param [Hash] raw. Raw data order.
      #
      # [
      #   'O5TDV2-WDYB2-6OGJRD',
      #   order_data: {
      #     'refid': nil, 'userref': nil, 'status': 'open', 'opentm': 1440292821.4839, 'starttm': 0, 'expiretm': 0,
      #     'descr': {
      #       'pair': 'ETHEUR', 'type': 'buy', 'ordertype': 'limit', 'price': '1.19000', 'price2': '0', 'leverage': 'none',
      #       'order': 'buy 1204.00000000 ETHEUR @ limit 1.19000'
      #     },
      #     'vol': '1204.00000000', 'vol_exec': '0.00000000', 'cost': '0.00000', 'fee': '0.00000', 'price': '0.00000',
      #     'misc': '', 'oflags': 'fciq'
      #   }
      # ]
      #
      # @return [BitexBot::Exchanges::Kraken::Order]
      def order_parser(id, raw)
        Order.new(
          id,
          order_types[raw[:descr][:type]],
          raw[:descr][:price].to_d,
          raw[:vol].to_d,
          raw[:opentm].truncate,
          order_statuses[raw[:status]],
          Hashie::Mash.new(raw.merge(id: id))
        )
      end

      def order_types
        @order_types ||= Hash.new(:undefined).merge('sell' => :ask, 'buy' => :bid).with_indifferent_access
      end

      def order_statuses
        @order_statuses ||= Hash.new(:undefined).merge('open' => :executing, 'closed' => :completed, 'cancelled' => :cancelled)
      end

      # @params [Array<BitexBot::Exchanges::Order>] parsed_orders.
      #
      # @returns [BigDecimal]
      def crypto_reserved(parsed_orders)
        parsed_orders.sum { |order| order.type == :ask ? order.amount - order.raw[:vol_exec].to_d : 0 }
      end

      # @params [Array<BitexBot::Exchanges::Order>] parsed_orders.
      #
      # @returns [BigDecimal]
      def fiat_reserved(parsed_orders)
        parsed_orders.sum { |order| order.type == :bid ? order.amount - order.raw[:vol_exec].to_d * order.price : 0 }
      end

      # @param [Hash] raws. Is a raw balances.
      #
      # { ZEUR: '1433.0939', XXBT: '0.0000000000', 'XETH': '99.7497224800' }
      #
      # @returns [BitexBot::Exchanges::BalanceSummary]
      def balance_summary_parser(raws) # rubocop:disable Metrics/AbcSize
        parsed_orders = orders
        BalanceSummary.new(
          balance_parser(raws[currency_pair.base].to_d, crypto_reserved(parsed_orders)),
          balance_parser(raws[currency_pair.quote].to_d, fiat_reserved(parsed_orders)),
          client.private.trade_volume(pair: currency_pair.altname)[:fees][currency_pair.code][:fee].to_d
        )
      end

      # @params [BigDecimal] total.
      # @params [BigDecimal] reserved.
      #
      # @returns [BitexBot::Exchanges::Balance]
      def balance_parser(total, reserved)
        Balance.new(total, reserved, total - reserved)
      end

      # @params [Hash(:asks, :bids)] raw. Raw orderbook.
      #
      # {
      #   'asks': [['204.52893', '0.010', 1440291148], ['204.78790', '0.312', 1440291132]],
      #   'bids': [['204.24000', '0.100', 1440291016], ['204.23010', '0.312', 1440290699]]
      # }
      #
      # @returns [BitexBot::Exchanges::Orderbook]
      def orderbook_parser(raw)
        Orderbook.new(Time.now.to_i, order_summary_parser(raw[:bids]), order_summary_parser(raw[:asks]))
      end

      # @params [Array<String:price, String:volume, Integer:timestamp>] raw_orders. Raw orders from raw orderbook.
      #
      # @returns [Array<BitexBot::Exchanges::OrderSummary>]
      def order_summary_parser(raw_orders)
        raw_orders.map { |raw| OrderSummary.new(raw[0].to_d, raw[1].to_d) }
      end

      # @param [Symbol] type <:buy|:sell>
      # @param [BigDecimal] price.
      # @param [BigDecimal] amount.
      #
      # @return [BitexBot::Exchanges::Order]
      def send_order(type, price, amount)
        client_order_id = closed_orders.first.try(:id)

        raw = client.private.add_order(
          pair: currency_pair.altname,
          type: type,
          ordertype: 'limit',
          price: price,
          volume: amount
        )

        order_by_id(raw[:txid]) if raw.present?
      end

      # @param [String] id.
      #
      # @returns [BitexBot::Exchanges::Order]
      def order_by_id(id)
        raw = client.private.query_orders(txid: id).first
        order_parser(*raw) if raw.present?
      end

      def find_lost(type, price, amount, threshold)
        price = price.truncate(5)
        order = find_lost_order(orders, type, price, amount, threshold)
        return order if order.present? && order.id != client_order_id

        order = find_lost_order(closed_orders, type, price, amount, threshold)
        order if order.present? && order.id != client_order_id
      end

      def find_lost_order(orders_to_query, type, price, amount, threshold)
        orders_to_query.find do |order|
          order.timestamp >= threshold.to_i && order.type == order_types[type] && order.price == price && order.amount == amount
        end
      end

      # @param [Time] start.
      #
      # @returns [Array<Hash(:id, :data)>]
      def closed_orders(start: 1.hour.ago)
        client
          .private.closed_orders(start: start.to_i)[:closed]
          .select { |_, data| data[:descr][:pair] == currency_pair.altname }
          .map { |id, data| order_parser(id, data.deep_symbolize_keys) }
      end

      # @param [Array<JsonLine>] raw.
      #
      # Kraken don't provides ID's for transaction, then we uses timestamp instead.
      #
      # [
      #   ['price', 'amount', 'timestamp', 'buy/sell', 'market/limit', 'miscellaneous']
      #   ['202.51626', '0.01440000', 1440277319.1922, 'b', 'l', ''],
      #   ['202.54000', '0.10000000', 1440277322.8993, 'b', 'l', '']
      # ]
      #
      # @teturns [BitexBot::Exchanges::Transaction]
      def transaction_parser(raw)
        Transaction.new(raw[2].truncate.to_s, raw[0].to_d, raw[1].to_d, raw[2].truncate, raw)
      end
    end
  end
end

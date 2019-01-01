module BitexBot
  # A workflow for selling bitcoin in Bitex and buying on another exchange. The SellOpeningFlow factory function estimates how
  # much you could buy on the other exchange and calculates a reasonable price taking into account the remote order book and the
  # recent operated volume.
  #
  # When created, a SellOpeningFlow places an Ask on Bitex for the calculated quantity and price, when the Ask is matched on
  # Bitex an OpenSell is created to buy the same quantity for a lower price on the other exchange.
  #
  # A SellOpeningFlow can be cancelled at any point, which will cancel the Bitex order and any orders on the remote exchange
  # created from its OpenSell's
  #
  # @attr order_id The first thing a SellOpeningFlow does is placing an Ask on Bitex, this is its unique id.
  class SellOpeningFlow < OpeningFlow
    # Start a workflow for selling bitcoin on bitex and buying on the other exchange. The quantity to be sold on bitex is
    # retrieved from Settings, if there is not enough BTC on bitex or USD on the other exchange then no order will be placed and
    # an exception will be raised instead.
    #
    # The amount a SellOpeningFlow will try to sell and the price it will try to charge are derived from these parameters:
    #
    # @param usd_balance [BigDecimal] amount of usd available in the other exchange that can be spent to balance this sale.
    # @param order_book [[price, quantity]] a list of lists representing an ask order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #   Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the BTC transacted.
    # @param maker_fee [BigDecimal] the transaction fee to pay on our maker exchange.
    # @param taker_fee [BigDecimal] the transaction fee to pay on the taker exchange.
    # @param store [Store] An updated config for this robot, mainly to use for profit.
    #
    # @return [SellOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for example when you run out of BTC on bitex or out
    # of USD on the other exchange.
    def self.create_for_market(usd_balance, order_book, transactions, maker_fee, taker_fee, store)
      super
    end

    # sync_open_positions helpers
    def self.transaction_order_id(transaction)
      transaction.ask_id
    end

    def self.open_position_class
      OpenSell
    end
    # end: sync_open_positions helpers

    # sought_transaction helpers
    def self.transaction_class
      Bitex::Sell
    end
    # end: sought_transaction helpers

    # create_for_market helpers
    def self.maker_price(fiat_to_spend_re_buying)
      fiat_to_spend_re_buying * fx_rate / value_to_use * (1 + profit / 100)
    end

    def self.order_class
      Bitex::Ask
    end
    def_delegator self, :order_class

    def self.order_type
      :sell
    end

    def self.profit
      store.selling_profit || Settings.selling.profit
    end

    def self.remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed * safest_price
    end

    def self.safest_price(transactions, taker_asks, bitcoins_to_use)
      OrderBookSimulator.run(Settings.time_to_live, transactions, taker_asks, nil, bitcoins_to_use, nil)
    end

    def self.value_to_use
      store.selling_quantity_to_sell_per_order || Settings.selling.quantity_to_sell_per_order
    end
    # end: create_for_market helpers

    def self.fx_rate
      Settings.selling_fx_rate
    end
  end
end

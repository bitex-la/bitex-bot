module BitexBot
  # A workflow for buying bitcoin in Bitex and selling on another exchange. The BuyOpeningFlow factory function estimates how
  # much you could sell on the other exchange and calculates a reasonable price taking into account the remote orderbook and the
  # recent operated volume.
  #
  # When created, a BuyOpeningFlow places a Bid on Bitex for the calculated amount and price, when the Bid is matched on Bitex an
  # OpenBuy is created to sell the matched amount for a higher price on the other exchange.
  #
  # A BuyOpeningFlow can be cancelled at any point, which will cancel the Bitex order and any orders on the remote exchange
  # created from its OpenBuy's
  #
  # @attr order_id The first thing a BuyOpeningFlow does is placing a Bid on Bitex, this is its unique id.
  #
  class BuyOpeningFlow < OpeningFlow
    # Start a workflow for buying bitcoin on bitex and selling on the other exchange. The amount to be spent on bitex is
    # retrieved from Settings, if there is not enough on USD bitex or BTC on the other exchange then no
    # order will be placed and an exception will be raised instead.
    #
    # The amount a BuyOpeningFlow will try to buy and the price it will try to buy at are derived from these parameters:
    #
    # @param btc_balance [BigDecimal] amount of btc available in the other exchange that can be sold to balance this purchase.
    # @param order_book [[price, quantity]] a list of lists representing a bid order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #   Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the BTC transacted.
    # @param bitex_fee [BigDecimal] the transaction fee to pay on bitex.
    # @param other_fee [BigDecimal] the transaction fee to pay on the other exchange.
    # @param store [Store] An updated config for this robot, mainly to use for profit.
    #
    # @return [BuyOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for example when you run out of USD on
    #   bitex or out of BTC on the other exchange.
    def self.create_for_market(btc_balance, order_book, transactions, bitex_fee, other_fee, store)
      super
    end

    # sync_open_positions helpers
    def self.transaction_order_id(transaction)
      transaction.bid_id
    end

    def self.open_position_class
      OpenBuy
    end
    # end: sync_open_positions helpers

    # sought_transaction helpers
    def self.transaction_class
      Bitex::Buy
    end
    # end: sought_transaction helpers

    # create_for_market helpers
    def self.maker_price(bitcoin_to_resell)
      (value_to_use / bitcoin_to_resell) * (1 - profit / 100.to_d)
    end

    def self.order_class
      Bitex::Bid
    end

    def self.profit
      store.buying_profit || Settings.buying.profit
    end

    def self.remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed / safest_price
    end

    def self.safest_price(transactions, order_book, dollars_to_use)
      OrderBookSimulator.run(Settings.time_to_live, transactions, order_book, dollars_to_use, nil)
    end

    def self.value_to_use
      store.buying_amount_to_spend_per_order || Settings.buying.amount_to_spend_per_order
    end
    # end: create_for_market helpers
  end
end

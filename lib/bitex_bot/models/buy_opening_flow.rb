module BitexBot
  # A workflow for buying bitcoin in Bitex and selling on another exchange. The BuyOpeningFlow factory function estimates how
  # much you could sell on the other exchange and calculates a reasonable price taking into account the remote order book and the
  # recent operated volume.
  #
  # When created, a BuyOpeningFlow places a Bid on Bitex for the calculated amount and price, when the Bid is matched on Bitex an
  # OpenBuy is created to sell the matched amount for a higher price on the other exchange.
  #
  # A BuyOpeningFlow can be cancelled at any point, which will cancel the Bitex order and any orders on the remote exchange
  # created from its OpenBuy's
  #
  # @attr order_id The first thing a BuyOpeningFlow does is placing a Bid on Bitex, this is its unique id.
  class BuyOpeningFlow < OpeningFlow
    # Start a workflow for buying bitcoin on bitex and selling on the other exchange. The amount to be spent on bitex is
    # retrieved from Settings, if there is not enough USD on bitex or BTC on the other exchange then no order will be placed
    # and an exception will be raised instead.
    #
    # The amount a BuyOpeningFlow will try to buy and the price it will try to buy at are derived from these parameters:
    #
    # @param btc_balance [BigDecimal] amount of btc available in the other exchange that can be sold to balance this purchase.
    # @param order_book [[price, quantity]] a list of lists representing a bid order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #   Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the BTC transacted.
    # @param maker_fee [BigDecimal] the transaction fee to pay on maker exchange.
    # @param taker_fee [BigDecimal] the transaction fee to pay on taker exchange.
    # @param store [Store] An updated config for this robot, mainly to use for profit.
    #
    # @return [BuyOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for example when you run out of USD on bitex or out
    #   of BTC on the other exchange.
    def self.open_market(taker_crypto_balance, maker_crypto_balance, taker_bids, taker_transactions, maker_fee, taker_fee, store)
      super
    end

    # @param [BigDecimal] crypto_to_resell.
    def self.maker_price(crypto_to_resell)
      value_to_use * fx_rate / crypto_to_resell * (1 - profit / 100)
    end

    # @param [ApiWrapper::UserTransaction] trade.
    def self.expected_kind_trade?(trade)
      trade.type.inquiry.buys?
    end

    def self.open_position_class
      OpenBuy
    end

    # TODO normalizar el uso de trade_type vs order_type
    def self.trade_type
      :buy
    end

    def self.order_type
      :bid
    end

    def self.profit
      store.try(:buying_profit) || Settings.buying.profit.to_d
    end

    def self.remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed / safest_price
    end

    def self.safest_price(taker_transactions, taker_bids, fiat_to_use)
      OrderBookSimulator.run(Settings.time_to_live, taker_transactions, taker_bids, fiat_to_use, nil, fx_rate)
    end

    def self.value_to_use
      store.try(:buying_amount_to_spend_per_order) || Settings.buying.amount_to_spend_per_order
    end

    def self.fx_rate
      Settings.buying_fx_rate
    end

    def self.value_per_order
      value_to_use * fx_rate
    end

    def self.maker_specie_to_spend
      Robot.maker.quote.upcase
    end

    def self.maker_specie_to_obtain
      Robot.maker.base.upcase
    end

    def self.taker_specie_to_spend
      Robot.taker.base.upcase
    end

    # Find order on maker bids.
    #
    # @param [String] order_id.
    #
    # @return [ApiWrapper::Order]
    def find_maker_order(order_id)
      Robot.maker.bid_by_id(order_id)
    end
  end
end

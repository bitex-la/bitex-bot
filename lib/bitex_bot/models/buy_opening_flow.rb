module BitexBot
  # A workflow for buying crypto specie in maker market and selling on taker market. The BuyOpeningFlow factory function
  # estimates how much you could sell on the other exchange and calculates a reasonable price taking into account the remote
  # orderbook and the recent operated volume.
  #
  # When created, a BuyOpeningFlow places a Bid on maker market for the calculated amount and price, when the Bid is matched on
  # maker market an OpenBuy is created to sell the matched amount for a higher price on the other exchange.
  #
  # A BuyOpeningFlow can be cancelled at any point, which will cancel the market market order and any orders on taker market
  # created from its OpenBuy's
  #
  # @attr order_id The first thing a BuyOpeningFlow does is placing a Bid on maker market, this is its unique id.
  class BuyOpeningFlow < OpeningFlow
    has_many :opening_orders, class_name: 'OpeningBid', foreign_key: :opening_flow_id

    cattr_accessor(:trade_type) { :buy }

    # Start a workflow for buying crypto specie on maker market and selling on taker market. The amount to be spent on maker
    # market is retrieved from Settings, if there is not enough FIAT on maker maket or CRYPTO on taker market then no order will
    # be placed and an exception will be raised instead.
    #
    # The amount a BuyOpeningFlow will try to buy and the price it will try to buy at are derived from these parameters:
    #
    # @param taker_crypto_balance [BigDecimal] amount of crypto available in the other exchange that can be sold to balance this
    # purchase.
    # @param order_book [[price, quantity]] a list of lists representing a bid order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #   Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the CRYPTO transacted.
    # @param maker_fee [BigDecimal] the transaction fee to pay on maker exchange.
    # @param taker_fee [BigDecimal] the transaction fee to pay on taker exchange.
    #
    # @return [BuyOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for example when you run out of FIAT on maker market
    # or out of CRYPTO on the taker market.
    def self.open_market(taker_crypto_balance, taker_bids, taker_transactions, maker_fee, taker_fee)
      super
    end

    # @param [BigDecimal] crypto_to_resell.
    def self.maker_price(crypto_to_resell)
      value_to_use * fx_rate / crypto_to_resell * (1 - profit / 100)
    end

    # @param [Exchanges::UserTransaction] trade.
    def self.expected_kind_trade?(trade)
      trade.type.inquiry.buys?
    end

    def self.open_position_class
      OpenBuy
    end

    def self.fx_rate
      Settings.buying_fx_rate
    end

    def self.profit
      Robot.store.try(:buying_profit) || Settings.buying.profit.to_d
    end

    def self.remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed / safest_price
    end

    def self.safest_price(taker_transactions, taker_bids, fiat_to_use)
      OrderbookSimulator.run(Settings.time_to_live, taker_transactions, taker_bids, fiat_to_use, nil, fx_rate)
    end

    def self.value_to_use
      Robot.store.try(:buying_amount_to_spend_per_order) || Settings.buying.amount_to_spend_per_order
    end

    def self.value_per_order
      value_to_use * fx_rate
    end

    def self.find_by_order_id(order_id)
      OpeningBid.find_by_order_id(order_id).try(:opening_flow)
    end

    def self.taker_specie_to_spend
      Robot.taker.base
    end

    # Find order on maker bids.
    #
    # @param [String] order_id.
    #
    # @return [Exchanges::Order]
    def find_maker_order(order_id)
      Robot.maker.bid_by_id(order_id)
    end

    # @param variation [Float] for cheaper orden on market deepening
    #
    # @return [BigDecimal]
    def price_scale(variation)
      price * (1 - variation)
    end
  end
end

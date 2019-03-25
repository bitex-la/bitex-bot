module BitexBot
  # A workflow for selling crypto specie in maker market and buying on taker market. The SellOpeningFlow factory function
  # estimates how much you could buy on the other exchange and calculates a reasonable price taking into account the remote
  # orderbook and the recent operated volume.
  #
  # When created, a SellOpeningFlow places an Ask on maker market for the calculated quantity and price, when the Ask is matched
  # on maker market an OpenSell is created to buy the same quantity for a lower price on taker market.
  #
  # A SellOpeningFlow can be cancelled at any point, which will cancel the maker maket order and any orders on taker market
  # created from its OpenSell's
  #
  # @attr order_id The first thing a SellOpeningFlow does is placing an Ask on maker market, this is its unique id.
  class SellOpeningFlow < OpeningFlow
    has_many :opening_orders, class_name: 'OpeningAsk', foreign_key: :opening_flow_id

    # Start a workflow for selling crypto specie on maker market and buying on taker market. The quantity to be sold on maker
    # market is retrieved from Settings, if there is not enough CRYPTO on maker market or FIAT on the taker market no order will
    # be placed and an exception will be raised instead.
    #
    # The amount a SellOpeningFlow will try to sell and the price it will try to charge are derived from these parameters:
    #
    # @param taker_fiat_balance [BigDecimal] amount of usd available in the other exchange that can be spent to balance this
    # sale.
    # @param order_book [[price, quantity]] a list of lists representing an ask order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #   Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the CRYPTO transacted.
    # @param maker_fee [BigDecimal] the transaction fee to pay on our maker exchange.
    # @param taker_fee [BigDecimal] the transaction fee to pay on the taker exchange.
    #
    # @return [SellOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for example when you run out of CRYPTO on maker market
    # or out of FIAT on taker market.
    def self.open_market(taker_fiat_balance, maker_crypto_balance, taker_asks, taker_transactions, maker_fee, taker_fee)
      super
    end

    # @param [BigDecimal] crypto_to_resell.
    def self.maker_price(fiat_to_spend_re_buying)
      fiat_to_spend_re_buying * fx_rate / value_to_use * (1 + profit / 100)
    end

    # @param [ApiWrapper::UserTransaction] trade.
    def self.expected_kind_trade?(trade)
      trade.type.inquiry.sells?
    end

    def self.open_position_class
      OpenSell
    end

    def self.trade_type
      :sell
    end
    def_delegator self, :trade_type

    def self.profit
      store.try(:selling_profit) || Settings.selling.profit
    end

    def self.remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed * safest_price
    end

    def self.safest_price(taker_transactions, taker_asks, cryptos_to_use)
      OrderbookSimulator.run(Settings.time_to_live, taker_transactions, taker_asks, nil, cryptos_to_use, nil)
    end

    def self.value_to_use
      store.try(:selling_quantity_to_sell_per_order) || Settings.selling.quantity_to_sell_per_order
    end

    def self.fx_rate
      Settings.selling_fx_rate
    end

    def self.value_per_order
      value_to_use
    end

    def self.find_by_order_id(order_id)
      OpeningAsk.find_by_order_id(order_id).try(:opening_flow)
    end

    def self.maker_specie_to_spend
      Robot.maker.base.upcase
    end

    def self.maker_specie_to_obtain
      Robot.maker.quote.upcase
    end

    def self.taker_specie_to_spend
      Robot.taker.quote.upcase
    end

    # Find order on maker asks.
    #
    # @param [String] order_id.
    #
    # @return [ApiWrapper::Order]
    def find_maker_order(order_id)
      Robot.maker.ask_by_id(order_id)
    end

    # @param variation [Float] for expensive orden on market deepening
    #
    # @return [BigDecimal]
    def price_scale(variation)
      price * (1 + variation)
    end
  end
end

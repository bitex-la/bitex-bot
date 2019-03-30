module BitexBot
  # It sold at maker market and needs to close (buy) on taker market.
  class BuyClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenBuy', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseBuy', foreign_key: :closing_flow_id

    def self.open_position_class
      OpenBuy
    end

    # @return [BigDecimal]
    def self.fx_rate
      Settings.buying_fx_rate
    end

    def self.trade_type
      :sell
    end

    # Scale price subtracting price variation.
    # Scale quantity taken new price.
    #
    # @return [Array[BigDecimal, BigDecimal]]
    def next_quantity_and_price
      next_price = desired_price - price_variation
      next_quantity = quantity - close_positions.sum(:quantity)

      [next_quantity, next_price]
    end

    private

    # The coins we actually bought minus the coins we were supposed to re-buy
    #
    # @return [BigDecimal]
    def estimate_crypto_profit
      quantity - close_positions.sum(:quantity)
    end

    # The amount received when selling initially, minus the amount spent re-buying the sold coins.
    #
    # @return [BigDecimal]
    def estimate_fiat_profit
      positions_balance_amount - open_positions.sum(:amount)
    end
  end
end

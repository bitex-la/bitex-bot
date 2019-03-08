module BitexBot
  # It bought at Bitex and needs to close (sell) in the other market.
  class SellClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenSell', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseSell', foreign_key: :closing_flow_id

    scope :active, -> { where(done: false) }

    def self.open_position_class
      OpenSell
    end

    # @return [BigDecimal]
    def self.fx_rate
      Settings.selling_fx_rate.to_d
    end
    def_delegator self, :fx_rate

    def self.trade_type
      :buy
    end

    # Scale price adding price variation.
    # Scañe quantity taken new price.
    #
    # @return [Array[BigDecimal, BigDecimal]]
    def next_quantity_and_price
      next_price = desired_price + price_variation
      next_quantity = ((quantity * desired_price) - close_positions.sum(:amount)) / next_price

      [next_quantity, next_price]
    end

    private

    # The coins we actually bought minus the coins we were supposed to re-buy.
    #
    # @return [BigDecimal]
    def estimate_crypto_profit
      close_positions.sum(:quantity) - quantity
    end

    # The amount received when selling initially, minus the amount spent re-buying the sold coins.
    #
    # @return [BigDecimal]
    def estimate_fiat_profit
      open_positions.sum(:amount) - positions_balance_amount
    end
  end
end

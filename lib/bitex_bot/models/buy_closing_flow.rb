module BitexBot
  ##
  # It sold at Bitex and needs to close (buy) in the other market.
  #
  class BuyClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenBuy', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseBuy', foreign_key: :closing_flow_id

    scope :active, -> { where(done: false) }

    class << self
      def open_position_class
        OpenBuy
      end
    end

    def order_method
      :sell
    end

    # The amount received when selling initially, minus the amount spent re-buying the sold coins.
    def estimate_usd_profit
      close_positions.sum(:amount) - open_positions.sum(:amount)
    end

    # The coins we actually bought minus the coins we were supposed to re-buy
    def estimate_btc_profit
      quantity - close_positions.sum(:quantity)
    end

    def next_price_and_quantity
      closes = close_positions
      next_price = desired_price - variation_price(closes.count)
      next_quantity = quantity - closes.sum(:quantity)
      [next_price, next_quantity]
    end
  end
end

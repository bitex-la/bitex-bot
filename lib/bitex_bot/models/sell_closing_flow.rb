module BitexBot
  ##
  # It bought at Bitex and needs to close (sell) in the other market.
  #
  class SellClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenSell', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseSell', foreign_key: :closing_flow_id

    scope :active, -> { where(done: false) }

    class << self
      def open_position_class
        OpenSell
      end
    end

    def order_method
      :buy
    end

    # The amount received when selling initially, minus the amount spent re-buying the sold coins.
    def estimate_usd_profit
      open_positions.sum(:amount) - close_positions.sum(:amount)
    end

    # The coins we actually bought minus the coins we were supposed to re-buy.
    def estimate_btc_profit
      close_positions.sum(:quantity) - quantity
    end

    def next_price_and_quantity
      closes = close_positions
      next_price = desired_price + variation_price(closes.count)
      next_quantity = ((quantity * desired_price) - closes.sum(:amount)) / next_price
      [next_price, next_quantity]
    end
  end
end

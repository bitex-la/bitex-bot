module BitexBot
  class BuyClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenBuy', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseBuy', foreign_key: :closing_flow_id
    scope :active, lambda { where(done: false) }

    def self.open_position_class
      OpenBuy
    end
      
    def order_method
      :sell
    end

    # The amount received when selling initially, minus
    # the amount spent re-buying the sold coins.
    def get_usd_profit
      close_positions.sum(:amount) - open_positions.sum(:amount)
    end
    
    # The coins we actually bought minus the coins we were supposed
    # to re-buy
    def get_btc_profit
      quantity - close_positions.sum(:quantity)
    end

    def get_next_price_and_quantity
      closes = close_positions
      next_price = desired_price - ((closes.count * (closes.count * 3)) / 100.0)
      next_quantity = quantity - closes.sum(:quantity)
      [next_price, next_quantity]
    end
  end
end

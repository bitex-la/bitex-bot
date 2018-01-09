module BitexBot
  class SellClosingFlow < ClosingFlow
    has_many :open_positions, class_name: 'OpenSell', foreign_key: :closing_flow_id
    has_many :close_positions, class_name: 'CloseSell', foreign_key: :closing_flow_id
    scope :active, ->{ where(done: false) }

    def self.open_position_class; OpenSell; end

    def order_method; :buy; end

    # The amount received when selling initially, minus
    # the amount spent re-buying the sold coins.
    def get_usd_profit
      open_positions.sum(:amount) - close_positions.sum(:amount)
    end

    # The coins we actually bought minus the coins we were supposed
    # to re-buy
    def get_btc_profit
      close_positions.sum(:quantity) - quantity
    end

    def get_next_price_and_quantity
      closes = close_positions
      next_price = desired_price + ((closes.count * (closes.count * 3)) / 100.0)
      next_quantity = ((quantity * desired_price) - closes.sum(:amount)) / next_price
      [next_price, next_quantity]
    end
  end
end

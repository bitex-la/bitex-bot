# Wrapper for bitfinex orders
class BitfinexOrder
  attr_accessor :id, :amount, :price, :type, :datetime

  def initialize(order_data)
    self.id = order_data['id'].to_i
    self.amount = order_data['original_amount'].to_d
    self.price = order_data['price'].to_d
    self.type = order_data['side'].to_sym
    self.datetime = order_data['timestamp'].to_i
  end

  def cancel!
    BitfinexApiWrapper.client.cancel_orders(id)
  end
end

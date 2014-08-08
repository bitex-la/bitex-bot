module BitexBot
  class ClosingFlow < ActiveRecord::Base
    self.abstract_class = true

    # Start a new CloseBuy that closes exising OpenBuy's by selling
    # on another exchange what was just bought on bitex.
    def self.close_open_positions
      open_positions = open_position_class.open
      return if open_positions.empty?

      quantity = open_positions.collect(&:quantity).sum
      amount = open_positions.collect(&:amount).sum
      suggested_amount = open_positions.collect do |open|
        open.quantity * open.opening_flow.suggested_closing_price
      end.sum
      price = suggested_amount / quantity

      # Don't even bother trying to close a position that's too small.
      return if quantity * price < minimum_amount_for_closing

      flow = create!(
        desired_price: price,
        quantity: quantity,
        amount: amount,
        open_positions: open_positions)
      
      flow.create_initial_order_and_close_position
      
      return flow
    end
    
    def create_initial_order_and_close_position
      create_order_and_close_position(quantity, desired_price)
    end

    def create_order_and_close_position(quantity, price)
      order = Bitstamp.orders.send(order_method,
        amount: quantity.round(4), price: price.round(2))
      if order.nil? || order.id.nil?
        Robot.logger.error("Closing: Error on #{order_method} for "\
          "#{self.class.name} ##{id} #{quantity} BTC @ $#{price}."\
          "#{order.to_s}")
        return
      end
      Robot.logger.info("Closing: Going to #{order_method} ##{order.id} for"\
        "#{self.class.name} ##{id} #{quantity} BTC @ $#{price}")
      close_positions.create!(order_id: order.id.to_i)
    end

    def sync_closed_positions(orders, transactions)
      latest_close = close_positions.last

      # Maybe we couldn't create the bitstamp order when this flow
      # was created, so we try again when syncing.
      if latest_close.nil?
        create_initial_order_and_close_position
        return
      end

      order = orders.find{|x| x.id.to_s == latest_close.order_id.to_s }
      
      # When ask is nil it means the other exchange is done executing it
      # so we can now have a look of all the sales that were spawned from it.
      if order.nil?
        closes = transactions.select{|t| t.order_id.to_s == latest_close.order_id.to_s}
        latest_close.amount = closes.collect{|x| x.usd.to_d }.sum.abs
        latest_close.quantity = closes.collect{|x| x.btc.to_d }.sum.abs
        latest_close.save!
        
        next_price, next_quantity = get_next_price_and_quantity
        if (next_quantity * next_price) > self.class.minimum_amount_for_closing
          create_order_and_close_position(next_quantity, next_price)
        else
          self.btc_profit = get_btc_profit
          self.usd_profit = get_usd_profit
          self.done = true
          Robot.logger.info("Closing: Finished #{self.class.name} ##{id}"\
            "earned $#{self.usd_profit} and #{self.btc_profit} BTC. ")
          save!
        end
      elsif latest_close.created_at < self.class.close_time_to_live.seconds.ago
        Robot.with_cooldown{ order.cancel! }
      end
    end
    
    # When placing a closing order we need to be aware of the smallest order
    # amount permitted by the other exchange.
    # If the other order is less than this USD amount then we do not attempt
    # to close the positions yet.
    def self.minimum_amount_for_closing
      5
    end
    
    def self.close_time_to_live
      60
    end
  end
end

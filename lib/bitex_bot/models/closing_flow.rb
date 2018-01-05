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

      flow
    end

    def create_initial_order_and_close_position
      create_order_and_close_position(quantity, desired_price)
    end

    def create_order_and_close_position(quantity, price)
      order = BitexBot::Robot.taker.place_order(
        order_method, price, quantity)

      if order.nil? || order.id.nil?
        unless order = sought_order(order_method, price)
          raise NotFoundOrder.new("Closing: #{order_method} not founded for "\
            "#{self.class.name} ##{id} #{quantity} BTC @ $#{price}."\
            "#{order.to_s}")
        end
      end

      Robot.logger.info("Closing: Going to #{order_method} ##{order.id} for "\
        "#{self.class.name} ##{id} #{order.amount} BTC @ $#{order.price}")
      close_positions.create!(order_id: order.id)
    end

    def sync_closed_positions(orders, transactions)
      latest_close = close_positions.last

      # Maybe we couldn't create the bitstamp order when this flow
      # was created, so we try again when syncing.
      if latest_close.nil?
        create_initial_order_and_close_position
        return
      end

      order_id = latest_close.order_id.to_s
      order = orders.find{|x| x.id.to_s == order_id }

      # When ask is nil it means the other exchange is done executing it
      # so we can now have a look of all the sales that were spawned from it.
      if order.nil?
        latest_close.amount, latest_close.quantity =
          BitexBot::Robot.taker.amount_and_quantity(order_id, transactions)
        latest_close.save!

        next_price, next_quantity = get_next_price_and_quantity
        if (next_quantity * next_price) > self.class.minimum_amount_for_closing
          create_order_and_close_position(next_quantity, next_price)
        else
          self.btc_profit = get_btc_profit
          self.usd_profit = get_usd_profit
          self.done = true
          Robot.logger.info("Closing: Finished #{self.class.name} ##{id} "\
            "earned $#{self.usd_profit} and #{self.btc_profit} BTC. ")
          save!
        end
      elsif latest_close.created_at < self.class.close_time_to_live.seconds.ago
        Robot.with_cooldown do
          begin
            Robot.logger.debug("Finalising #{order.class}##{order.id}")
            order.cancel!
            Robot.logger.debug("Finalised #{order.class}##{order.id}")
          rescue StandardError => e
            nil # just pass, we'll keep on trying until it's not in orders anymore.
          end
        end
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
      30
    end

    private

    def sought_order(order_method, price)
      20.times do
        BitexBot::Robot.sleep_for 10
        order = BitexBot::Robot.taker.find_recent_orders(order_method, price)
        return order if order.present?
      end
      return
    end
  end
end

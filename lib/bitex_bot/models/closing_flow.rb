module BitexBot
  class ClosingFlow < ActiveRecord::Base
    self.abstract_class = true

    class << self

      def close_time_to_live
        30
      end

      # Start a new CloseBuy that closes exising OpenBuy's by selling
      # on another exchange what was just bought on bitex.
      def close_open_positions
        open_positions = open_position_class.open
        return if open_positions.empty?

        quantity = open_positions.collect(&:quantity).sum
        amount = open_positions.collect(&:amount).sum
        suggested_amount = open_positions.collect do |open|
          open.quantity * open.opening_flow.suggested_closing_price
        end.sum
        price = suggested_amount / quantity

        # Don't even bother trying to close a position that's too small.
        return unless BitexBot::Robot.taker.enough_order_size?(quantity, price)

        flow = create!(
          desired_price: price,
          quantity: quantity,
          amount: amount,
          open_positions: open_positions)

        flow.create_initial_order_and_close_position  # May raise OrderNotFound
        return
      end
    end

    def create_initial_order_and_close_position
      create_order_and_close_position(quantity, desired_price)
    end

    def create_order_and_close_position(quantity, price)
      # TODO ver de que manera generar un ID para insertar en los campos metas donde sea posible.
      Robot.logger.info("Closing: Going to place #{order_method} order for #{self.class.name}"\
        " ##{id} #{quantity} BTC @ $#{price}")
      order = BitexBot::Robot.taker.place_order(order_method, price, quantity)
      close_positions.create!(order_id: order.id)
    end

    # TODO should receive a order_ids and user_transaccions array,
    # then each Wrapper should know how to search for them internally.
    def sync_closed_positions(orders, transactions)
      latest_close = close_positions.last

      # Maybe we couldn't create the bitstamp order when this flow
      # was created, so we try again when syncing.
      if latest_close.nil?
        create_initial_order_and_close_position
        return
      end

      order_id = latest_close.order_id.to_s
      order = orders.find { |o| o.id.to_s == order_id }

      # When order is nil it means the other exchange is done executing it
      # so we can now have a look of all the sales that were spawned from it.
      if order.nil?
        latest_close.amount, latest_close.quantity =
          BitexBot::Robot.taker.amount_and_quantity(order_id, transactions)
        latest_close.save!

        next_price, next_quantity = next_price_and_quantity

        if BitexBot::Robot.taker.enough_order_size?(next_quantity, next_price)
          create_order_and_close_position(next_quantity, next_price)
        else
          self.btc_profit = estimate_btc_profit
          self.usd_profit = estimate_usd_profit
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

    def estimate_btc_profit
      raise 'self subclass responsibility'
    end

    def estimate_usd_profit
      raise 'self subclass responsibility'
    end

    def next_price_and_quantity
      raise 'self subclass responsibility'
    end
  end
end

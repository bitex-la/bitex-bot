module BitexBot
  ##
  # Close buy/sell positions.
  #
  class ClosingFlow < ActiveRecord::Base
    self.abstract_class = true

    cattr_reader(:close_time_to_live) { 30 }

    # Start a new CloseBuy that closes exising OpenBuy's by selling on another exchange what was just bought on bitex.
    def self.close_open_positions
      open_positions = open_position_class.open
      return if open_positions.empty?

      quantity = open_positions.map(&:quantity).sum
      amount = open_positions.map(&:amount).sum
      price = suggested_amount(open_positions) / quantity

      # Don't even bother trying to close a position that's too small.
      return unless BitexBot::Robot.taker.enough_order_size?(quantity, price)
      create_closing_flow!(price, quantity, amount, open_positions)
    end

    # close_open_positions helpers
    def self.suggested_amount(positions)
      positions.map { |p| p.quantity * p.opening_flow.suggested_closing_price }.sum
    end

    def self.create_closing_flow!(price, quantity, amount, open_positions)
      create!(desired_price: price, quantity: quantity, amount: amount, open_positions: open_positions)
        .create_initial_order_and_close_position!
      nil
    end
    # end: close_open_positions helpers

    def create_initial_order_and_close_position!
      create_order_and_close_position(quantity, desired_price)
    end

    # TODO: should receive a order_ids and user_transaccions array, then each Wrapper should know how to search for them.
    def sync_closed_positions(orders, transactions)
      # Maybe we couldn't create the bitstamp order when this flow was created, so we try again when syncing.
      latest_close.nil? ? create_initial_order_and_close_position! : create_or_cancel!(orders, transactions)
    end

    private

    # sync_closed_positions helpers
    def create_or_cancel!(orders, transactions)
      order_id = latest_close.order_id
      order = orders.find { |o| o.id.to_s == order_id }

      # When order is nil it means the other exchange is done executing it so we can now have a look of all the sales that were
      # spawned from it.
      if order.nil?
        sync_position(order_id, transactions)
        create_next_position!
      elsif expired?
        cancel!(order)
      end
    end

    def latest_close
      close_positions.last
    end

    def expired?
      latest_close.created_at < close_time_to_live.seconds.ago
    end
    # end: sync_closed_positions helpers

    # create_or_cancel! helpers
    def cancel!(order)
      Robot.with_cooldown do
        Robot.log(:debug, "Finalising #{order.class}##{order.id}")
        order.cancel!
        Robot.log(:debug, "Finalised #{order.class}##{order.id}")
      end
    rescue StandardError
      nil # just pass, we'll keep on trying until it's not in orders anymore.
    end

    # This use hooks methods, these must be defined in the subclass:
    #   estimate_btc_profit
    #   estimate_usd_profit
    #   next_price_and_quantity
    def create_next_position!
      next_price, next_quantity = next_price_and_quantity
      return create_order_and_close_position(next_quantity, next_price) if enough_order_size?(next_quantity, next_price)

      update!(btc_profit: estimate_btc_profit, usd_profit: estimate_usd_profit, done: true)
      Robot.log(:info, "Closing: Finished #{self.class.name} ##{id} earned $#{usd_profit} and #{btc_profit} BTC.")
      save!
    end

    def enough_order_size?(quantity, price)
      BitexBot::Robot.taker.enough_order_size?(quantity, price)
    end

    def sync_position(order_id, transactions)
      latest_close.tap do |latest|
        latest.amount, latest.quantity = BitexBot::Robot.taker.amount_and_quantity(order_id, transactions)
      end.save!
    end
    # end: create_or_cancel! helpers

    # next_price_and_quantity helpers
    def price_variation(closes_count)
      closes_count**2 * 0.03
    end
    # end: next_price_and_quantity helpers

    # This use hooks methods, these must be defined in the subclass:
    #   order_method
    def create_order_and_close_position(quantity, price)
      # TODO: investigate how to generate an ID to insert in the fields of goals where possible.
      Robot.log(:info, "Closing: Going to place #{order_method} order for #{self.class.name} ##{id} #{quantity} BTC @ $#{price}")
      order = Robot.taker.place_order(order_method, price, quantity)
      close_positions.create!(order_id: order.id)
    end
  end
end

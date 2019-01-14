module BitexBot
  # Close buy/sell positions.
  class ClosingFlow < ActiveRecord::Base
    extend Forwardable

    self.abstract_class = true

    cattr_reader(:close_time_to_live) { 30 }

    # Start a new CloseBuy that closes existing OpenBuy's by selling on another exchange what was just bought on bitex.
    def self.close_open_positions
      return unless open_positions.any?

      positions = open_positions
      quantity = positions.sum(&:quantity)
      amount = positions.sum(&:amount) / fx_rate
      price = suggested_amount(positions) / quantity
      unless Robot.taker.enough_order_size?(quantity, price)
        Robot.log(
          :info,
          "Closing: #{Robot.taker.name} - enough order size for #{Robot.taker.base.upcase} #{quantity}"\
          " @ #{Robot.taker.quote.upcase} #{price}"
        )

      end

      create_closing_flow!(price, quantity, amount, positions)
    end

    def self.open_positions
      open_position_class.open
    end

    # close_open_positions helpers
    def self.suggested_amount(positions)
      positions.map { |p| p.quantity * p.opening_flow.suggested_closing_price }.sum
    end

    def self.create_closing_flow!(price, quantity, amount, open_positions)
      flow = create!(desired_price: price, quantity: quantity, amount: amount, open_positions: open_positions)
      Robot.log(
        :debug,
        "Closing: created #{self}##{flow.id}, desired price: #{flow.desired_price}, quantity: #{flow.quantity}, amount: #{flow.amount}.\n"
      )
      flow.create_initial_order_and_close_position!
      nil
    end
    # end: close_open_positions helpers

    def create_initial_order_and_close_position!
      create_order_and_close_position(quantity, desired_price)
    end

    # TODO: should receive a order_ids and user_transaccions array, then each Wrapper should know how to search for them.
    def sync_closed_positions
      # Maybe we couldn't create the bitstamp order when this flow was created, so we try again when syncing.
      latest_close.nil? ? create_initial_order_and_close_position! : create_or_cancel!
    end

    def estimate_fiat_profit
      raise 'self subclass responsibility'
    end

    def positions_balance_amount
      close_positions.sum(:amount) * fx_rate
    end

    private

    # sync_closed_positions helpers
    # rubocop:disable Metrics/AbcSize
    def create_or_cancel!
      order_id = latest_close.order_id.to_s
      order = Robot.with_cooldown { Robot.taker.orders.find { |o| o.id.to_s == order_id } }

      # When order is nil it means the other exchange is done executing it so we can now have a look of all the sales that were
      # spawned from it.
      if order.nil?
        sync_position(order_id)
        create_next_position!
      elsif latest_close.created_at < close_time_to_live.seconds.ago
        cancel!(order)
      end
    end
    # rubocop:enable Metrics/AbcSize

    def latest_close
      close_positions.last
    end
    # end: sync_closed_positions helpers

    # create_or_cancel! helpers
    def cancel!(order)
      Robot.with_cooldown do
        Robot.log(:debug, "Finalising #{order.raw.class}##{order.id}")
        order.cancel!
        Robot.log(:debug, "Finalised #{order.raw.class}##{order.id}")
      end
    rescue StandardError => error
      Robot.log(:debug, error)
      nil # just pass, we'll keep on trying until it's not in orders anymore.
    end

    # This use hooks methods, these must be defined in the subclass:
    #   estimate_crypto_profit
    #   amount_positions_balance
    #   next_price_and_quantity
    # rubocop:disable Metrics/AbcSize
    def create_next_position!
      next_price, next_quantity = next_price_and_quantity
      if Robot.taker.enough_order_size?(next_quantity, next_price)
        create_order_and_close_position(next_quantity, next_price)
      else
        update!(crypto_profit: estimate_crypto_profit, fiat_profit: estimate_fiat_profit, fx_rate: fx_rate, done: true)
        Robot.log(
          :info,
          "Closing: Finished #{self.class} ##{id} earned"\
          " #{Robot.maker.quote.upcase} #{fiat_profit} and #{Robot.maker.base.upcase} #{crypto_profit}."
        )
      end
    end
    # rubocop:enable Metrics/AbcSize

    def sync_position(order_id)
      latest = latest_close
      latest.amount, latest.quantity = Robot.taker.amount_and_quantity(order_id)
      latest.save!
    end
    # end: create_or_cancel! helpers

    # next_price_and_quantity helpers
    def price_variation(closes_count)
      closes_count**2 * 0.03
    end
    # end: next_price_and_quantity helpers

    # This use hooks methods, these must be defined in the subclass:
    #   order_type
    def create_order_and_close_position(quantity, price)
      # TODO: investigate how to generate an ID to insert in the fields of goals where possible.
      Robot.log(
        :info,
        "Closing: Going to place #{order_type} order for #{self.class} ##{id}"\
        " #{Robot.taker.base.upcase} #{quantity} @ #{Robot.taker.quote.upcase} #{price}"
      )
      order = Robot.taker.place_order(order_type, price, quantity)
      Robot.log(
        :debug,
        "Closing: #{Robot.taker.name} placed #{order.type} with price: #{order.price} @ quantity #{order.amount}.\n"\
        "Closing: Going to create Close#{order.type.to_s.capitalize} position.\n"
      )

      close_positions.create!(order_id: order.id)
    end
  end
end

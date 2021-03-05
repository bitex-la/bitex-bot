module BitexBot
  # Close buy/sell positions.
  class ClosingFlow < ActiveRecord::Base
    extend Forwardable

    self.abstract_class = true

    cattr_reader(:close_time_to_live) { Settings.close_time_to_live }

    # Start a new CloseBuy that closes existing OpenBuy's by selling on taker market what was just bought on maker market.
    # rubocop:disable Metrics/AbcSize
    def self.close_market
      return unless open_position_class.open.any?

      positions = open_position_class.open
      quantity = positions.sum(&:quantity)
      price = (suggested_amount(positions) / quantity)
      return unless Robot.taker.enough_order_size?(quantity, price)

      order = Robot.taker.place_order(trade_type, price, quantity)
      Robot.log(:info, "Closing: placed #{trade_type} with price: #{order.price} @ quantity #{order.amount}.")

      amount = positions.sum(&:amount) / fx_rate

      create!(desired_price: price, quantity: quantity, amount: amount, open_positions: positions).tap do |flow|
        flow.close_positions.create!(order_id: order.id)
      end
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end
    # rubocop:enable Metrics/AbcSize

    # In this steps if exist anyone active closing flow, asume that also will has a anyone close position.
    # rubocop:disable Metrics/AbcSize
    def self.sync_positions
      active.each do |flow|
        latest = flow.close_positions.last
        next Robot.taker.cancel_order(latest.order) if latest.cancellable?

        next unless latest.executed?

        latest.sync

        quantity, price = flow.next_quantity_and_price
        next flow.finalise! unless Robot.taker.enough_order_size?(quantity, price)

        Robot.taker.place_order(trade_type, price, quantity).tap do |order|
          flow.close_positions.create!(order_id: order.id)
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    # @param [Array<OpenBuy>|Array<OpenSell>]
    #
    # @return [BigDecimal]
    def self.suggested_amount(positions)
      positions.sum { |p| p.quantity * p.opening_flow.suggested_closing_price }
    end

    private_class_method :suggested_amount

    def finalise!
      Robot.log(
        :info,
        "Closing: Finished #{self.class} ##{id} earned"\
        " fiat profit: #{estimate_fiat_profit} and crypto profit: #{estimate_crypto_profit}."
      )
      update(crypto_profit: estimate_crypto_profit, fiat_profit: estimate_fiat_profit, fx_rate: fx_rate, done: true)
    end

    private

    def positions_balance_amount
      close_positions.sum(:amount) * fx_rate
    end

    # Used for progressive scale when trying to place a hitteable order on taker.
    # Its use closes count as attempts count.
    #
    # @return [BigDecimal]
    def price_variation
      close_positions.count**2 * 0.3.to_d
    end
  end
end

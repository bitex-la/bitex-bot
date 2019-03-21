module BitexBot
  # Shared behaviour for position clousure.
  module CloseableTrade
    extend ActiveSupport::Concern

    included do
      def sync
        trades_amount, trades_quantity = Robot.taker.amount_and_quantity(order_id)

        update(amount: trades_amount, quantity: trades_quantity)
      end

      def cancellable?
        !executed? && expired?
      end

      def executed?
        order.nil?
      end

      def order
        @order ||= Robot.with_cooldown do
          Robot.taker.orders.find { |o| o.id == order_id }
        end
      end

      private

      def expired?
        created_at < Settings.close_time_to_live.seconds.ago
      end
    end
  end
end

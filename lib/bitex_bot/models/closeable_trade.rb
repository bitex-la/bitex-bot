module BitexBot
  # Shared behaviour for position clousure.
  module CloseableTrade
    extend ActiveSupport::Concern

    included do # rubocop:disable Metrics/BlockLength
      after_commit -> { Robot.log(:info, :closing, :placement, summary) }, on: :create
      after_commit -> { Robot.log(:info, :closing, :sync, summary) }, on: :update

      validates_presence_of :order_id

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
        created_at < Settings.close_time_to_live.seconds.ago.utc
      end

      def summary
        "#{closing_flow.class} ##{closing_flow.id}: "\
          "order_id: #{order_id}, "\
          "desired_price: #{Robot.maker.quote} #{closing_flow.desired_price}, "\
          "amount: #{Robot.maker.base} #{amount}, "\
          "quantity: #{Robot.maker.quote} #{quantity}."
      end
    end
  end
end

module BitexBot
  # Represents an order placed by opening flow on maker market.
  class OpeningOrder < ActiveRecord::Base
    # With this roles, define actions when be hitted, cancelled, etc
    enum role: %i[no_role first_tip second_tip support informant final]

    # Statuses:
    #   executing: The maker order has been placed, its id stored as order_id.
    #   settling: In process of cancelling the maker order and any other outstanding order in the taker exchange.
    #   completed: Successfully hit.
    #   finalised: Successfully settled or cancelled.
    enum status: %i[executing settling finalised]

    validates_presence_of :role, inclusion: { in: roles }
    validates_presence_of :status, inclusion: { in: statuses }
    validates_presence_of :amount, :price, :order_id

    def finalise
      return if finalised?

      if order_finalisable?
        Robot.notify("#{self.class} #{role} with id #{id} was hit") if informant? && order.status == :completed
        return finalised!
      end
      return if settling?

      Robot.maker.cancel_order(order)
      settling!
    end

    def resume
      "#{opening_flow.trade_type}: #{order_id}"\
        ", status: #{status}, price: #{price}, amount: #{amount * opening_flow.class.fx_rate}"
    end

    def order_finalisable?
      order.status == :cancelled || order.status == :completed
    end

    private

    def order
      @order ||= Robot.with_cooldown { Robot.maker.order_by_id(opening_flow.trade_type, order_id) }
    end
  end
end

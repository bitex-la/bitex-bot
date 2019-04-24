module BitexBot
  # Shared behaviour for position opening.
  module OpenableTrade
    extend ActiveSupport::Concern

    included do
      scope :open, -> { where(closing_flow: nil) }

      after_commit -> { Robot.log(:info, :opening, :sync, hit_summary) }, on: :create

      validates_presence_of :amount, :quantity, :price, :transaction_id

      private

      def hit_summary
        "#{opening_flow.class} ##{opening_flow.id} on order_id ##{transaction_id} was hit for "\
          "#{Robot.maker.base} #{quantity} @ #{Robot.maker.quote} #{price}."
      end
    end
  end
end

module BitexBot
  # Shared behaviour for position opening.
  module OpenableTrade
    extend ActiveSupport::Concern

    included do
      scope :open, -> { where(closing_flow: nil) }

      after_commit -> { Robot.log(:info, :opening, :sync, hit_summary) }, on: :create

      private

      def hit_summary
        "#{opening_flow.class} ##{opening_flow.id} on order_id ##{transaction_id} was hit for "\
          "#{Robot.maker.base.upcase} #{quantity} @ #{Robot.maker.quote.upcase} #{price}."
      end
    end
  end
end

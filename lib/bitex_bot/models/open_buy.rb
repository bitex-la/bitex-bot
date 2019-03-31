module BitexBot
  # An OpenBuy represents a Buy transaction on maker market.
  # OpenBuys are open buy positions that are closed by one or several CloseBuys.
  class OpenBuy < ActiveRecord::Base
    include OpenableTrade

    belongs_to :opening_flow, class_name: 'BuyOpeningFlow', foreign_key: :opening_flow_id
    belongs_to :closing_flow, class_name: 'BuyClosingFlow', foreign_key: :closing_flow_id
  end
end

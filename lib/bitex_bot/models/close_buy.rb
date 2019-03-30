module BitexBot
  # A CloseBuy represents an Ask on the remote exchange intended to close one or several OpenBuy positions.
  class CloseBuy < ActiveRecord::Base
    belongs_to :closing_flow, class_name: BuyClosingFlow.name, foreign_key: :closing_flow_id

    include CloseableTrade
  end
end

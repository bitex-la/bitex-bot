module BitexBot
  # A CloseBuy represents an Ask on the remote exchange intended to close one or several OpenBuy positions.
  class CloseSell < ActiveRecord::Base
    belongs_to :closing_flow, class_name: 'SellClosingFlow', foreign_key: :closing_flow_id

    include CloseTrade
  end
end

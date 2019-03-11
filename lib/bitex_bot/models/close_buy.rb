module BitexBot
  # A CloseBuy represents an Ask on the remote exchange intended to close one or several OpenBuy positions.
  class CloseBuy < ActiveRecord::Base
    cattr_accessor :closing_flow_class { BuyClosingFlow }

    include CloseableTrade
  end
end

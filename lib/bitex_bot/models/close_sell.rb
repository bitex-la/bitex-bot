module BitexBot
  # A CloseBuy represents an Ask on the remote exchange intended to close one or several OpenBuy positions.
  class CloseSell < ActiveRecord::Base
    cattr_accessor :closing_flow_class { SellClosingFlow }

    include CloseableTrade
  end
end

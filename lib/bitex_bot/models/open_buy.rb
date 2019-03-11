module BitexBot
  # An OpenBuy represents a Buy transaction on Bitex.
  # OpenBuys are open buy positions that are closed by one or several CloseBuys.
  class OpenBuy < ActiveRecord::Base
    cattr_accessor :opening_flow_class { BuyOpeningFlow }
    cattr_accessor :closing_flow_class { BuyClosingFlow }

    include OpenableTrade
  end
end

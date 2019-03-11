module BitexBot
  # An OpenSell represents a Sell transaction on Bitex.
  # OpenSells are open sell positions that are closed by one SellClosingFlow.
  class OpenSell < ActiveRecord::Base
    cattr_accessor :opening_flow_class { BitexBot::SellOpeningFlow }
    cattr_accessor :closing_flow_class { BitexBot::SellClosingFlow }

    include OpenableTrade
  end
end

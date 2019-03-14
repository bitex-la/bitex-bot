module BitexBot
  # An OpenSell represents a Sell transaction on maker market.
  # OpenSells are open sell positions that are closed by one SellClosingFlow.
  class OpenSell < ActiveRecord::Base
    cattr_accessor(:opening_flow_class) { SellOpeningFlow }
    cattr_accessor(:closing_flow_class) { SellClosingFlow }

    include OpenableTrade
  end
end

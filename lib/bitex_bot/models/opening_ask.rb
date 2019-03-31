module BitexBot
  # Ask reference placed by opening flow on maker market.
  class OpeningAsk < OpeningOrder
    belongs_to :opening_flow, class_name: 'SellOpeningFlow'
  end
end

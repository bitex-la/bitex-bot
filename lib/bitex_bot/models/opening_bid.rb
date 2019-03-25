module BitexBot
  # Bid reference placed by opening flow on maker market.
  class OpeningBid < OpeningOrder
    belongs_to :opening_flow, class_name: 'BuyOpeningFlow'
  end
end

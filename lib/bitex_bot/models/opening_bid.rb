module BitexBot
  class OpeningBid < OpeningOrder
    belongs_to :opening_flow, class_name: 'BuyOpeningFlow'
  end
end

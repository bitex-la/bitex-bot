module BitexBot
  class OpeningAsk < OpeningOrder
    belongs_to :opening_flow, class_name: 'SellOpeningFlow'
  end
end

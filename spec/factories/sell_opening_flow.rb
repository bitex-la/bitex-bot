FactoryBot.define do
  factory :sell_opening_flow, class: BitexBot::SellOpeningFlow do
    order_id                12_345
    price                   300.to_d
    value_to_use            2.to_d
    suggested_closing_price 290.to_d
    status                  'executing'
  end

  factory :other_sell_opening_flow, class: BitexBot::SellOpeningFlow do
    order_id                2
    price                   400.to_d
    value_to_use            1.to_d
    suggested_closing_price 390.to_d
    status                  'executing'
  end
end

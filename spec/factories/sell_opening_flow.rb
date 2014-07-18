FactoryGirl.define do
  factory :sell_opening_flow, class: BitexBot::SellOpeningFlow do
    price 300.0
    value_to_use 2.0
    suggested_closing_price 290.0
    status 'executing'
    order_id 12345
  end

  factory :other_sell_opening_flow, class: BitexBot::SellOpeningFlow do
    price 400.0
    value_to_use 1.0
    suggested_closing_price 390.0
    status 'executing'
    order_id 2
  end
end

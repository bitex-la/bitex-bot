FactoryGirl.define do
  factory :buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price 300.0
    value_to_use 600.0
    suggested_closing_price 310.0
    status 'executing'
    order_id 12345
  end

  factory :other_buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price 400.0
    value_to_use 400.0
    suggested_closing_price 410.0
    status 'executing'
    order_id 2
  end
end

FactoryBot.define do
  factory :buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    order_id                 12_345
    price                   300.to_d
    value_to_use            600.to_d
    suggested_closing_price 310.to_d
    status                  'executing'
  end

  factory :other_buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    order_id                2
    price                   400.to_d
    value_to_use            400.to_d
    suggested_closing_price 410.to_d
    status                  'executing'
  end
end

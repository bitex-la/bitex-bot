FactoryBot.define do
  factory :buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price                   { 300 }
    value_to_use            { 600 }
    suggested_closing_price { 310 }
    status                  { :executing }
  end

  factory :other_buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price                   { 400 }
    value_to_use            { 400 }
    suggested_closing_price { 410 }
    status                  { :executing }
  end
end

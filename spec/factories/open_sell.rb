FactoryBot.define do
  factory :open_sell, class: BitexBot::OpenSell do
    price 300.0
    amount 600.0
    quantity 2.0
    transaction_id 12345678
    association :opening_flow, factory: :sell_opening_flow
  end

  factory :tiny_open_sell, class: BitexBot::OpenSell do
    price 400.0
    amount 4.0
    quantity 0.01
    transaction_id 23456789
    association :opening_flow, factory: :other_sell_opening_flow
  end
end

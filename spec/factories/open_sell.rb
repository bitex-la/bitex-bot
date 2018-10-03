FactoryBot.define do
  factory :open_sell, class: BitexBot::OpenSell do
    association :opening_flow, factory: :sell_opening_flow

    transaction_id { 12345678 }
    price          { 300 }
    amount         { 600 }
    quantity       { 2 }
  end

  factory :tiny_open_sell, class: BitexBot::OpenSell do
    association :opening_flow, factory: :other_sell_opening_flow

    transaction_id { 23456789 }
    price          { 400 }
    amount         { 4 }
    quantity       { 0.01 }
  end
end

FactoryBot.define do
  factory :open_buy, class: BitexBot::OpenBuy do
    association :opening_flow, factory: :buy_opening_flow

    transaction_id 12_345_678
    price          300.to_d
    amount         600.to_d
    quantity       2.to_d
  end

  factory :tiny_open_buy, class: BitexBot::OpenBuy do
    association :opening_flow, factory: :other_buy_opening_flow 

    transaction_id 23_456_789
    price          400.to_d
    amount         4.to_d
    quantity       0.01.to_d
  end
end

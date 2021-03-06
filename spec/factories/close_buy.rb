FactoryBot.define do
  factory :close_buy, class: BitexBot::CloseBuy do
    sequence(:id)

    order_id { '1' }
    quantity { 2 }
    amount   { 220 }
  end
end

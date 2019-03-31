FactoryBot.define do
  factory :close_sell, class: BitexBot::CloseSell do
    association :closing_flow, factory: :sell_closing_flow

    sequence(:id)

    order_id { '1' }
    quantity { 2 }
    amount   { 220 }
  end
end

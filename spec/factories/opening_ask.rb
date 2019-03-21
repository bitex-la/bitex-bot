FactoryBot.define do
  factory :opening_ask, class: BitexBot::OpeningAsk do
    factory(BitexBot::OpeningAsk)

    association :opening_flow, factory: :sell_opening_flow

    sequence(:id)

    order_id { 'ask#1' }
    amount   { 2 }
    price    { 4_000 }
    role     { :first_tip }
    status   { :executing }
  end
end

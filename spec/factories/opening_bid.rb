FactoryBot.define do
  factory :opening_bid, class: BitexBot::OpeningBid do
    association :opening_flow, factory: :buy_opening_flow

    sequence(:id)

    order_id { 'bid#1' }
    amount   { 2 }
    price    { 4_000 }
    role     { :first_tip }
    status   { :executing }
  end
end

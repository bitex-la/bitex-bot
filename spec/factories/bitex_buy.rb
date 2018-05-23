FactoryBot.define do
  factory :bitex_buy, class: Bitex::Buy do
    id 12345678
    created_at { Time.now }
    order_book :btc_usd
    quantity 2.0
    amount 600.0
    fee 0.05
    price 300.0
    bid_id 12345
  end
end

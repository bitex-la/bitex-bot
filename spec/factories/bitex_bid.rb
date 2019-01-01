FactoryBot.define do
  factory :bitex_bid, class: Bitex::Bid do
    id                { 12_345_678 }
    created_at        { Time.now }
    order_book        { :btc_usd }
    price             { 1_000.to_d }
    status            { :received }
    reason            { :not_cancelled }
    issuer            { 'User#1' }
    amount            { 100.to_d }
    remaining_amount  { 100.to_d }
    produced_quantity { 10.to_d }
  end
end

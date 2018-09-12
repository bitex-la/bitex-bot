FactoryBot.define do
  factory :bitex_sell, class: Bitex::Sell do
    id         { 12_345_678 }
    created_at { Time.now }
    order_book { :btc_usd }
    quantity   { 2.0.to_d }
    amount     { 600.0.to_d }
    fee        { 0.05.to_d }
    price      { 300.0.to_d }
    ask_id     { 12_345 }
  end
end

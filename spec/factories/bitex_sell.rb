FactoryBot.define do
  factory :bitex_sell, class: Bitex::Sell do
    id         12_345_678
    ask_id     12_345
    orderbook  :btc_usd
    quantity   2.to_d
    amount     600.to_d
    fee        0.05.to_d
    price      300.to_d
    created_at Time.now
  end
end

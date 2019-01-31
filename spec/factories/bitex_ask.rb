FactoryBot.define do
  factory :bitex_ask, class: Bitex::Resources::Orders::Ask do
    id                 { '12345678' }
    type               { 'asks' }
    orderbook_code     { 'btc_usd' }
    amount             { '100' }
    remaining_amount   { '100' }
    price              { '1000' }
    status             { 'received' }
  end
end

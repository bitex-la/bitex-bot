FactoryBot.define do
  factory :buy_closing_flow, class: BitexBot::BuyClosingFlow do
    sequence(:id)

    desired_price  { 110 }
    quantity       { 2 }
    amount         { 220 }
    done           { true }
    crypto_profit  { 1 }
    fiat_profit    { 10 }
    fx_rate        { 1 }
  end
end

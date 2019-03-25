FactoryBot.define do
  factory :buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price                   { 300 }
    value_to_use            { 600 }
    suggested_closing_price { 310 }
    status                  { :executing }

    transient do
      orders { [] }
    end

    after(:create) do |flow, evaluator|
      evaluator.orders.each do |order|
        create(:opening_bid, attributes_for(:opening_bid).merge(order).merge(opening_flow: flow))
      end
    end
  end

  factory :other_buy_opening_flow, class: BitexBot::BuyOpeningFlow do
    price                   { 400 }
    value_to_use            { 400 }
    suggested_closing_price { 410 }
    status                  { :executing }
  end
end

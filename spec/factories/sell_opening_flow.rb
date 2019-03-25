FactoryBot.define do
  factory :sell_opening_flow, class: BitexBot::SellOpeningFlow do
    price                   { 300 }
    value_to_use            { 2 }
    suggested_closing_price { 290 }
    status                  { :executing }

    transient do
      orders { [] }
    end

    after(:create) do |flow, evaluator|
      evaluator.orders.each do |order|
        create(:opening_ask, attributes_for(:opening_ask).merge(order).merge(opening_flow: flow))
      end
    end
  end

  factory :other_sell_opening_flow, class: BitexBot::SellOpeningFlow do
    price                   { 400.0 }
    value_to_use            { 1.0 }
    suggested_closing_price { 390.0 }
    status                  { :executing }
  end
end

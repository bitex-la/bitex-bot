FactoryBot.define do
  factory :store, class: BitexBot::Store do
    maker_fiat   { 0 }
    maker_crypto { 0 }
    taker_fiat   { 0 }
    taker_crypto { 0 }
  end
end

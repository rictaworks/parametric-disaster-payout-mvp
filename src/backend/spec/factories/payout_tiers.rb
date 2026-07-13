FactoryBot.define do
  factory :payout_tier do
    sequence(:code) { |n| "tier_#{n}" }
    amount_yen { 10_000 }
    labels { nil }
  end
end

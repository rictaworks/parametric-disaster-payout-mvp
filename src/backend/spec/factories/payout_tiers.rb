FactoryBot.define do
  factory :payout_tier do
    association :plan
    threshold { 5.0 }
    amount { 100_000.0 }
    tier_label { "震度5弱" }
  end
end

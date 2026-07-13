FactoryBot.define do
  factory :policy do
    association :user
    association :plan
    association :station
    association :payout_tier
    association :policy_status, :waiting
    threshold { 4.5 }
    waiting_until { 72.hours.from_now }
    expires_at { 1.year.from_now }
  end
end

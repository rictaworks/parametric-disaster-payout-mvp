FactoryBot.define do
  factory :plan do
    plan_type { "seismic" }
    sequence(:name) { |n| "地震プラン#{n}" }
    description { "地震保険デモプラン" }
  end
end

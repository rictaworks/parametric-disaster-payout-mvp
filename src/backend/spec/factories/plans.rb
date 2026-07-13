FactoryBot.define do
  factory :plan do
    sequence(:code) { |n| "plan_#{n}" }
    plan_type { "seismic" }
    labels { nil }

    trait :seismic do
      code { "seismic_plan" }
      plan_type { "seismic" }
    end

    trait :rainfall do
      code { "rainfall_plan" }
      plan_type { "rainfall" }
    end
  end
end

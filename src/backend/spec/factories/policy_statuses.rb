FactoryBot.define do
  factory :policy_status do
    sequence(:code) { |n| "status_#{n}" }
    labels { nil }

    trait :waiting do
      code { PolicyStatus::WAITING }
    end

    trait :active do
      code { PolicyStatus::ACTIVE }
    end

    trait :processing do
      code { PolicyStatus::PROCESSING }
    end

    trait :cap_reached do
      code { PolicyStatus::CAP_REACHED }
    end

    trait :cancelled do
      code { PolicyStatus::CANCELLED }
    end

    trait :lapsed do
      code { PolicyStatus::LAPSED }
    end
  end
end

FactoryBot.define do
  factory :station do
    sequence(:code) { |n| "station_#{n}" }
    station_type { "seismic" }
    labels { nil }

    trait :seismic do
      station_type { "seismic" }
    end

    trait :rainfall do
      station_type { "rainfall" }
    end
  end
end

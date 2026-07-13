FactoryBot.define do
  factory :user do
    sequence(:google_sub) { |n| "google_sub_#{n}" }
  end
end

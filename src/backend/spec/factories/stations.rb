FactoryBot.define do
  factory :station do
    sequence(:code) { |n| "STATION#{n.to_s.rjust(5, '0')}" }
    sequence(:name) { |n| "観測所#{n}" }
    prefecture { "東京都" }
  end
end

class Policy < ApplicationRecord
  AGE_GROUPS = %w[under_20 20s 30s 40s 50s 60s over_70].freeze

  belongs_to :user
  belongs_to :plan
  belongs_to :station
  belongs_to :payout_tier
  belongs_to :policy_status

  validates :threshold, presence: true
  validates :age_group, inclusion: { in: AGE_GROUPS }, allow_nil: true
end

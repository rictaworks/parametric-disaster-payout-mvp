class Policy < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  belongs_to :station
  belongs_to :payout_tier
  belongs_to :policy_status

  has_many :payouts
  has_many :notifications

  validates :threshold, presence: true
  validates :waiting_until, presence: true
  validates :expires_at, presence: true

  ACTIVE_STATUS_CODES = [
    PolicyStatus::WAITING,
    PolicyStatus::ACTIVE,
    PolicyStatus::PROCESSING
  ].freeze
end

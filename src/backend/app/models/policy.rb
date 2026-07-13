class Policy < ApplicationRecord
  STATUSES = %w[active cancelled expired limit_reached].freeze
  ANNUAL_PAYOUT_LIMIT = 2

  belongs_to :user
  belongs_to :plan
  belongs_to :station
  belongs_to :payout_tier
  has_many :payouts
  has_many :notifications

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validates :annual_payout_count, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: "active") }

  def limit_reached?
    annual_payout_count >= ANNUAL_PAYOUT_LIMIT
  end
end

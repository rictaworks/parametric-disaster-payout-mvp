class Payout < ApplicationRecord
  STATUSES = %w[pending completed].freeze

  belongs_to :policy
  belongs_to :observation, optional: true
  has_many :notifications

  validates :amount, :status, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
end

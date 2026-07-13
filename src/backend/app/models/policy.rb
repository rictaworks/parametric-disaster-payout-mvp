class Policy < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  belongs_to :payout_tier
  belongs_to :policy_status

  has_many :observations, dependent: :destroy
  has_many :payouts, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :survey_responses, dependent: :destroy

  validates :threshold, presence: true
  validates :expires_at, presence: true

  before_validation :set_default_expires_at, on: :create

  private

  def set_default_expires_at
    self.expires_at ||= Time.current + 1.year
  end
end

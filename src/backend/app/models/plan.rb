class Plan < ApplicationRecord
  has_many :payout_tiers
  has_many :policies

  validates :plan_type, presence: true, inclusion: { in: %w[seismic rainfall] }
  validates :name, presence: true
end

class PayoutTier < ApplicationRecord
  belongs_to :plan

  validates :threshold, :amount, :tier_label, presence: true
end

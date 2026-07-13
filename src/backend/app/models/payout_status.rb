class PayoutStatus < ApplicationRecord
  has_many :payouts

  INSTRUCTED = "instructed"
  COMPLETED  = "completed"
  VOIDED     = "voided"

  validates :code, presence: true, uniqueness: true
end

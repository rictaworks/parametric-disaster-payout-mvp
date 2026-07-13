class Payout < ApplicationRecord
  belongs_to :policy
  belongs_to :payout_status
  belongs_to :observation

  validates :idempotency_key, presence: true, uniqueness: true
  validates :amount_yen, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end

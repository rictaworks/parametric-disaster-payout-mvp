class Payout < ApplicationRecord
  belongs_to :policy
  belongs_to :payout_tier
  belongs_to :payout_status
  belongs_to :observation, optional: true

  validates :idempotency_key, presence: true, uniqueness: true
end

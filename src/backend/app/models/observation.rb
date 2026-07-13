class Observation < ApplicationRecord
  belongs_to :station
  has_many :payouts

  validates :observed_at, :value, :event_id, presence: true
end

class ObservationEvent < ApplicationRecord
  belongs_to :observation

  validates :occurred_at, presence: true
  validates :payload, presence: true
end

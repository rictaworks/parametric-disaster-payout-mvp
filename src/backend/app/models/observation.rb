class Observation < ApplicationRecord
  belongs_to :station
  belongs_to :seismic_intensity_level, optional: true

  has_many :payouts

  validates :observed_at, presence: true
  validates :value, presence: true
end

class Station < ApplicationRecord
  has_many :policies
  has_many :observations

  validates :code, presence: true, uniqueness: true
  validates :station_type, presence: true, inclusion: { in: %w[seismic rainfall] }
end

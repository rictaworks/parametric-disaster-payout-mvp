class SeismicIntensityLevel < ApplicationRecord
  has_many :observations

  validates :code, presence: true, uniqueness: true
  validates :numeric_value, presence: true
end

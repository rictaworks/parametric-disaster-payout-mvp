class Observation < ApplicationRecord
  belongs_to :policy
  belongs_to :station
  belongs_to :seismic_intensity_level, optional: true

  validates :observed_at, presence: true
  validate :measurement_matches_station

  private

  def measurement_matches_station
    return if station.blank?

    case station.measurement_type
    when "seismic"
      errors.add(:seismic_intensity_level, :blank) if seismic_intensity_level.blank?
      errors.add(:rainfall_mm, "must be blank for seismic stations") if rainfall_mm.present?
    when "rainfall"
      errors.add(:rainfall_mm, :blank) if rainfall_mm.blank?
      errors.add(:seismic_intensity_level, "must be blank for rainfall stations") if seismic_intensity_level.present?
    end
  end
end

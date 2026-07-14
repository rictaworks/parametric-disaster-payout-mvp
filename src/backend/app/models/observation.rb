class Observation < ApplicationRecord
  belongs_to :station
  belongs_to :seismic_intensity_level, optional: true
  has_many :payouts

  validates :observed_at, presence: true

  validate :seismic_station_requires_event_id_and_intensity
  validate :rainfall_station_requires_rainfall_value_and_no_event_id
  validate :attributes_cannot_be_changed_if_referenced_by_payouts, on: :update
  validate :seismic_intensity_cannot_decrease, on: :update
  validate :rainfall_mm_cannot_decrease, on: :update

  validates :event_id, uniqueness: { scope: :station_id }, allow_nil: true
  validates :observed_at, uniqueness: { scope: :station_id }, if: -> { event_id.nil? }

  before_validation :normalize_event_id

  private

  def normalize_event_id
    self.event_id = nil if event_id.blank?
  end

  def seismic_station_requires_event_id_and_intensity
    return if station.blank?
    return unless station.measurement_type == "seismic"

    if event_id.blank?
      errors.add(:event_id, :blank)
    end

    if seismic_intensity_level.blank?
      errors.add(:seismic_intensity_level, :blank)
    end

    if rainfall_mm.present?
      errors.add(:rainfall_mm, :must_be_blank_for_seismic_stations)
    end
  end

  def rainfall_station_requires_rainfall_value_and_no_event_id
    return if station.blank?
    return unless station.measurement_type == "rainfall"

    if rainfall_mm.blank?
      errors.add(:rainfall_mm, :blank)
    end

    if event_id.present?
      errors.add(:event_id, :blank)
    end

    if seismic_intensity_level.present?
      errors.add(:seismic_intensity_level, :must_be_blank_for_rainfall_stations)
    end
  end

  def attributes_cannot_be_changed_if_referenced_by_payouts
    return unless payouts.exists?

    if station_id_changed?
      errors.add(:station, :locked_by_payouts)
    end

    if event_id_changed?
      errors.add(:event_id, :locked_by_payouts)
    end

    if observed_at_changed?
      errors.add(:observed_at, :locked_by_payouts)
    end
  end

  def seismic_intensity_cannot_decrease
    return unless seismic_intensity_level_id_changed?
    return if seismic_intensity_level_id_was.nil?

    old_level = SeismicIntensityLevel.find_by(id: seismic_intensity_level_id_was)
    new_level = seismic_intensity_level

    if old_level && new_level && new_level.sort_order < old_level.sort_order
      errors.add(:seismic_intensity_level, :cannot_decrease_from_previous_value)
    end
  end

  def rainfall_mm_cannot_decrease
    return unless rainfall_mm_changed?
    return if rainfall_mm_was.nil? || rainfall_mm.nil?

    if rainfall_mm < rainfall_mm_was
      errors.add(:rainfall_mm, :cannot_decrease_from_previous_value)
    end
  end
end

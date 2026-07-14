class Policy < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  belongs_to :station, optional: true
  belongs_to :payout_tier
  belongs_to :policy_status

  has_many :payouts, dependent: :destroy
  has_many :notifications, dependent: :destroy

  validates :threshold, presence: true
  validates :station, presence: true, on: :create
  validates :waiting_until, presence: true, on: :create
  validates :expires_at, presence: true

  validate :plan_trigger_matches_station_measurement
  validate :attributes_cannot_be_changed_if_payouts_exist, on: :update
  validate :station_and_waiting_until_cannot_be_set_to_nil_if_previously_present, on: :update
  validate :waiting_until_cannot_be_moved_forward, on: :update

  before_validation :set_default_waiting_until, on: :create
  before_validation :set_default_expires_at, on: :create

  private

  def set_default_waiting_until
    self.waiting_until = Time.current + 72.hours
  end

  def set_default_expires_at
    self.expires_at ||= Time.current + 1.year
  end

  def plan_trigger_matches_station_measurement
    return if plan.blank? || station.blank?

    if plan.trigger_type != station.measurement_type
      errors.add(:station, :measurement_type_must_match_plan_trigger_type)
    end
  end

  def attributes_cannot_be_changed_if_payouts_exist
    return unless payouts.exists?

    if user_id_changed?
      errors.add(:user, :locked_by_existing_payouts)
    end
    if station_id_changed?
      errors.add(:station, :locked_by_existing_payouts)
    end
    if payout_tier_id_changed?
      errors.add(:payout_tier, :locked_by_existing_payouts)
    end
    if plan_id_changed?
      errors.add(:plan, :locked_by_existing_payouts)
    end
    if threshold_changed?
      errors.add(:threshold, :locked_by_existing_payouts)
    end
    if waiting_until_changed?
      errors.add(:waiting_until, :locked_by_existing_payouts)
    end
  end

  def station_and_waiting_until_cannot_be_set_to_nil_if_previously_present
    if station_id_was.present? && station_id.nil?
      errors.add(:station, :cannot_be_removed_once_set)
    end

    if waiting_until_was.present? && waiting_until.nil?
      errors.add(:waiting_until, :cannot_be_removed_once_set)
    end
  end

  def waiting_until_cannot_be_moved_forward
    return unless waiting_until_changed?
    return if waiting_until_was.nil? || waiting_until.nil?

    if waiting_until < waiting_until_was
      errors.add(:waiting_until, :cannot_be_moved_forward)
    end
  end
end

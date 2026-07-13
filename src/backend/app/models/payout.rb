class Payout < ApplicationRecord
  belongs_to :policy
  belongs_to :payout_tier
  belongs_to :payout_status
  belongs_to :observation

  has_one :survey_response, dependent: :destroy

  validates :idempotency_key, presence: true, uniqueness: true

  validate :payout_tier_matches_policy
  validate :observation_matches_policy_station
  validate :observation_must_be_after_policy_waiting_until
  validate :policy_and_observation_cannot_be_changed, on: :update

  private

  def payout_tier_matches_policy
    return if policy.blank? || payout_tier.blank?

    if payout_tier != policy.payout_tier
      errors.add(:payout_tier, "must match policy payout tier")
    end
  end

  def observation_matches_policy_station
    return if policy.blank? || observation.blank?

    if observation.station_id != policy.station_id
      errors.add(:observation, "must match policy station")
    end
  end

  def observation_must_be_after_policy_waiting_until
    return if policy.blank? || observation.blank?

    if observation.observed_at < policy.waiting_until
      errors.add(:observation, "observed_at must be after policy waiting_until")
    end
  end

  def policy_and_observation_cannot_be_changed
    if policy_id_changed?
      errors.add(:policy, "cannot be changed once created")
    end

    if observation_id_changed?
      errors.add(:observation, "cannot be changed once created")
    end
  end
end

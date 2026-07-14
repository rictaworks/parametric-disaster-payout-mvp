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
      errors.add(:payout_tier, :must_match_policy_payout_tier)
    end
  end

  def observation_matches_policy_station
    return if policy.blank? || observation.blank?

    if observation.station_id != policy.station_id
      errors.add(:observation, :must_match_policy_station)
    end
  end

  def observation_must_be_after_policy_waiting_until
    return if policy.blank? || observation.blank?

    if observation.observed_at < policy.waiting_until
      errors.add(:observation, :observed_at_must_be_after_policy_waiting_until)
    end
  end

  def policy_and_observation_cannot_be_changed
    if policy_id_changed?
      errors.add(:policy, :immutable_once_created)
    end

    if observation_id_changed?
      errors.add(:observation, :immutable_once_created)
    end
  end
end

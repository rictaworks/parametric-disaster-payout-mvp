class SurveyResponse < ApplicationRecord
  belongs_to :user
  belongs_to :payout

  validates :response_data, presence: true
  validates :payout_id, uniqueness: true

  validate :user_matches_payout_user
  validate :payout_status_must_be_completed

  private

  def user_matches_payout_user
    return if user.blank? || payout.blank?

    if user_id != payout.policy&.user_id
      errors.add(:user, :must_be_policy_owner)
    end
  end

  def payout_status_must_be_completed
    return if payout.blank?
    return unless Payout.column_names.include?("payout_status_id")
    return if payout.payout_status.nil?

    if payout.payout_status.code != "completed_simulated"
      errors.add(:payout, :must_be_completed_to_accept_survey)
    end
  end
end

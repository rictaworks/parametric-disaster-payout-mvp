class SurveyResponse < ApplicationRecord
  belongs_to :user
  belongs_to :payout

  validates :response_data, presence: true
  validates :payout_id, uniqueness: true

  validate :user_matches_payout_user

  private

  def user_matches_payout_user
    return if user.blank? || payout.blank?

    if user_id != payout.policy&.user_id
      errors.add(:user, :must_be_policy_owner)
    end
  end
end

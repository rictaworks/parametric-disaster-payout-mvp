class SurveyResponse < ApplicationRecord
  belongs_to :user
  belongs_to :payout

  validates :response_data, presence: true
  validates :payout_id, uniqueness: true

  validate :user_matches_payout_user
  validate :payout_status_must_be_completed
  validate :satisfaction_must_be_valid, on: :create

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

  def satisfaction_must_be_valid
    data = response_data
    if data.is_a?(String)
      data = JSON.parse(data) rescue {}
    end

    data = data.with_indifferent_access if data.respond_to?(:with_indifferent_access)

    satisfaction = data ? (data[:satisfaction] || data["satisfaction"]) : nil

    if satisfaction.nil?
      errors.add(:response_data, :satisfaction_required)
      return
    end

    is_valid_integer =
      if satisfaction.is_a?(Integer)
        true
      elsif satisfaction.is_a?(String) && satisfaction.match?(/\A\d+\z/)
        true
      else
        false
      end

    unless is_valid_integer
      errors.add(:response_data, :satisfaction_not_integer)
      return
    end

    satisfaction_val = satisfaction.to_i
    unless (1..5).include?(satisfaction_val)
      errors.add(:response_data, :satisfaction_out_of_range)
    end
  end
end

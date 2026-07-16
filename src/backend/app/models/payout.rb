class Payout < ApplicationRecord
  belongs_to :policy
  belongs_to :payout_tier
  belongs_to :payout_status
  belongs_to :observation

  has_one :survey_response, dependent: :destroy

  validates :idempotency_key, presence: true, uniqueness: true

  # 契約の現在の利用可否を判定するための年間支払回数なので、確定させた支払が紐づく
  # 観測の年ではなく、現在時刻の年（Time.current.year）を基準に集計する。
  # 管理画面の一覧表示（Admin::PoliciesController）とトリガー判定後の状態更新の
  # 双方から参照する共通ロジックとして、ここに一本化する
  def self.annual_completed_counts(policy_ids: nil, year: Time.current.year)
    invalid_status = PayoutStatus.find_by(code: "invalid")
    year_range = Time.zone.local(year, 1, 1).beginning_of_day..Time.zone.local(year, 12, 31).end_of_day

    scope = joins(:observation).where(observations: { observed_at: year_range })
    scope = scope.where.not(payout_status: invalid_status) if invalid_status.present?
    scope = scope.where(policy_id: policy_ids) if policy_ids
    scope.group(:policy_id).count
  end

  validate :payout_tier_matches_policy
  validate :observation_matches_policy_station
  validate :observation_must_be_after_policy_waiting_until
  validate :policy_and_observation_cannot_be_changed, on: :update

  after_save :update_policy_status_on_state_change, if: :saved_change_to_payout_status_id?

  private

  TERMINAL_POLICY_STATUS_CODES = %w[cancelled expired].freeze

  def update_policy_status_on_state_change
    completed_status = PayoutStatus.find_by(code: "completed_simulated")
    invalid_status = PayoutStatus.find_by(code: "invalid")
    ordered_status = PayoutStatus.find_by(code: "ordered")

    return unless payout_status == completed_status || payout_status == invalid_status

    policy.with_lock do
      # 支払指図後に契約が解約・失効していた場合、終端状態を支払確定処理で上書きしない
      next if TERMINAL_POLICY_STATUS_CODES.include?(policy.policy_status.code)

      # processing のまま契約期間（expires_at）を過ぎていた場合、通常の active/cap_reached への
      # 復帰は行わず先に失効させる。満期チェックを行わないステータスコードのみの判定だと、
      # 満了後に支払が確定した瞬間だけ一時的に「有効」と誤表示されてしまう
      if policy.expires_at <= Time.current
        policy.update!(policy_status: PolicyStatus.find_by!(code: "expired"))
        next
      end

      # 同一契約に未処理（ordered）の支払が他に残っている間は processing を維持し、
      # 全ての支払が確定（完了または無効化）してから active / cap_reached を確定する
      next if policy.payouts.where(payout_status: ordered_status).exists?

      next_status_code = annual_payout_count_at_or_above_limit? ? "cap_reached" : "active"
      policy.update!(policy_status: PolicyStatus.find_by!(code: next_status_code))
    end
  end

  # 年をまたいだ前年分の ordered 支払が最後に確定した場合でも、当年の実績で判定されるようにする
  def annual_payout_count_at_or_above_limit?
    self.class.annual_completed_counts(policy_ids: [ policy_id ]).fetch(policy_id, 0) >= 2
  end

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

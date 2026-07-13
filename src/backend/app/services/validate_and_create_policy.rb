require "net/http"
require "uri"
require "json"

# F1: 契約登録サービス
# reCAPTCHA検証・マスタ存在確認・重複契約拒否・「待機中」での契約作成・免責明け時刻（72時間後）の記録
# 本サービスは保険（デモ）であり実際の金銭のお支払いは発生しません。
class ValidateAndCreatePolicy
  WAITING_PERIOD_HOURS = 72
  POLICY_DURATION_YEARS = 1

  Result = Struct.new(:success?, :policy, :error, :error_code, keyword_init: true)

  def initialize(user:, plan_id:, station_id:, payout_tier_id:, recaptcha_token:)
    @user           = user
    @plan_id        = plan_id
    @station_id     = station_id
    @payout_tier_id = payout_tier_id
    @recaptcha_token = recaptcha_token
  end

  def call
    unless recaptcha_valid?
      return Result.new(success?: false, error: "reCAPTCHA verification failed", error_code: :recaptcha_failed)
    end

    plan = Plan.find_by(id: @plan_id)
    station = Station.find_by(id: @station_id)
    payout_tier = PayoutTier.find_by(id: @payout_tier_id)

    unless plan && station && payout_tier
      return Result.new(success?: false, error: "Invalid plan, station, or payout tier", error_code: :master_not_found)
    end

    if duplicate_active_policy?(plan)
      return Result.new(success?: false, error: "Active policy already exists for this plan type", error_code: :duplicate_policy)
    end

    waiting_status = PolicyStatus.find_by!(code: PolicyStatus::WAITING)
    now = Time.current

    policy = Policy.create!(
      user:          @user,
      plan:          plan,
      station:       station,
      payout_tier:   payout_tier,
      policy_status: waiting_status,
      threshold:     default_threshold(plan),
      waiting_until: now + WAITING_PERIOD_HOURS.hours,
      expires_at:    now + POLICY_DURATION_YEARS.year
    )

    Result.new(success?: true, policy: policy)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message, error_code: :validation_error)
  end

  private

  def recaptcha_valid?
    secret = ENV.fetch("RECAPTCHA_SECRET_KEY", nil)
    return true if secret.blank? && !Rails.env.test?

    uri = URI("https://www.google.com/recaptcha/api/siteverify")
    response = Net::HTTP.post_form(uri, secret: secret.to_s, response: @recaptcha_token)
    result = JSON.parse(response.body)
    result["success"] == true
  rescue StandardError
    false
  end

  def duplicate_active_policy?(plan)
    active_status_ids = PolicyStatus
      .where(code: Policy::ACTIVE_STATUS_CODES)
      .pluck(:id)

    @user.policies
      .joins(:plan)
      .where(plans: { plan_type: plan.plan_type })
      .where(policy_status_id: active_status_ids)
      .exists?
  end

  def default_threshold(plan)
    case plan.plan_type
    when "seismic"
      SeismicIntensityLevel.find_by(code: "5_lower")&.numeric_value || 4.5
    when "rainfall"
      50.0
    else
      0.0
    end
  end
end

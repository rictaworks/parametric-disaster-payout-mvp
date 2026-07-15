class ValidateAndCreatePolicy
  Result = Struct.new(:policy, :status, :error, :details, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(user:, plan_id:, station_id:, payout_tier_id:, threshold:, recaptcha_token:)
    @user = user
    @plan_id = plan_id
    @station_id = station_id
    @payout_tier_id = payout_tier_id
    @threshold = threshold
    @recaptcha_token = recaptcha_token
  end

  def call
    return failure(:bad_request, "recaptcha_failed") unless recaptcha_valid?

    masters = load_masters
    missing_masters = masters.select { |_, value| value.nil? }.keys
    return failure(:unprocessable_entity, "master_not_found", missing_masters) if missing_masters.any?

    return failure(:unprocessable_entity, "threshold_invalid") unless threshold_valid?(masters)

    policy, duplicate = create_policy_within_lock(masters)

    return failure(:conflict, "duplicate_policy") if duplicate
    return Result.new(policy: policy, status: :created) if policy.persisted?

    failure(:unprocessable_entity, "validation_failed", policy.errors.to_hash(true))
  end

  private

  attr_reader :user, :plan_id, :station_id, :payout_tier_id, :threshold, :recaptcha_token

  def recaptcha_valid?
    RecaptchaVerifier.new.valid?(recaptcha_token)
  end

  def load_masters
    {
      plan: Plan.find_by(id: plan_id),
      station: Station.find_by(id: station_id),
      payout_tier: PayoutTier.find_by(id: payout_tier_id),
      pending_status: PolicyStatus.find_by(code: "pending"),
      active_status: PolicyStatus.find_by(code: "active"),
      processing_status: PolicyStatus.find_by(code: "processing")
    }
  end

  def threshold_valid?(masters)
    case masters.fetch(:plan).trigger_type
    when "seismic"
      SeismicIntensityLevel.exists?(label_ja: threshold)
    when "rainfall"
      normalized_rainfall_threshold.present?
    else
      true
    end
  end

  # 検証を通過した値はそのまま Policy#threshold に保存する。RainfallThresholdParser は
  # evaluate_trigger.rb でも同じ解析ロジックとして使われるため、ここで正規化した数値文字列は
  # 評価時にも問題なく解析できる
  def normalized_rainfall_threshold
    return @normalized_rainfall_threshold if defined?(@normalized_rainfall_threshold)

    value = RainfallThresholdParser.parse(threshold)
    @normalized_rainfall_threshold = value&.to_s("F")
  end

  def create_policy_within_lock(masters)
    policy = nil
    duplicate = false

    ActiveRecord::Base.transaction do
      user.lock!

      if duplicate_policy_exists?(masters)
        duplicate = true
        raise ActiveRecord::Rollback
      end

      policy = Policy.new(
        user: user,
        plan: masters.fetch(:plan),
        station: masters.fetch(:station),
        payout_tier: masters.fetch(:payout_tier),
        policy_status: masters.fetch(:pending_status),
        threshold: policy_threshold(masters)
      )
      policy.save
    end

    [ policy, duplicate ]
  end

  def policy_threshold(masters)
    masters.fetch(:plan).trigger_type == "rainfall" ? normalized_rainfall_threshold : threshold
  end

  def duplicate_policy_exists?(masters)
    Policy.joins(:plan).where(
      user_id: user.id,
      plans: { trigger_type: masters.fetch(:plan).trigger_type },
      policy_status_id: [
        masters.fetch(:pending_status),
        masters.fetch(:active_status),
        masters.fetch(:processing_status)
      ].compact.map(&:id)
    ).exists?
  end

  def failure(status, error, details = nil)
    Result.new(status: status, error: error, details: details)
  end
end

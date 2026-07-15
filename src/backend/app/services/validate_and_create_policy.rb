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

    return failure(:conflict, "duplicate_policy") if duplicate_policy_exists?(masters)

    policy = Policy.new(
      user: user,
      plan: masters.fetch(:plan),
      station: masters.fetch(:station),
      payout_tier: masters.fetch(:payout_tier),
      policy_status: masters.fetch(:pending_status),
      threshold: threshold
    )

    return Result.new(policy: policy, status: :created) if policy.save

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
